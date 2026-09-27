-- Migration: att_engine_fixes_audit (WS-B, Ripple Map v6, engine method 6.1, 2026-09-26)
-- Fixes the blockers and should-fix items of the independent statistical audit (scratchpad/v5/ENGINE_AUDIT.md):
--   B1 positive-control fixtures resolve to the geo-annotated control events (slug lookup, fixture meta), arrays cover a series'
--      whole history (≤ 7 y), the TSA national expectation is replaced by regional targets, HN (attention) is no longer "expected Measured";
--   B2 null scale: 1.4826·MAD over pre-onset windows only (ending ≥ L + 30 d before the onset, trailing 3 y, PHYS skips 2020-03..2021-06),
--      floors 0.5 (peak) / 1.0 (CAR), degenerate series (< 20 % distinct windows) excluded from ž; cache keyed on the hop's onset month;
--   B3 season-matched date placebos on every channel; < 2 prior years → capped at Likely; per-channel L frozen at freeze (template L honoured);
--   B4 holidays (US federal ±1 d, Christmas week, Black Friday) registered as common days; panel rule "≥ 30 % |z| ≥ 2"; onset OR window peak
--      day flagged; geo_filter honoured in att_resolve_targets;
--   B5 nightly att_reexamine over settled Likely/Measured hops (new look rows ≥ 100, own frozen BH family, existing retraction branch, ledger);
--      parent retraction / demotion propagates to children;
--   S1 BH on p_h (the more conservative input; spec §5.2 as written); S3 duplicate paths merged at freeze (alt_paths); S4 graph read as of
--      onset − 1 and the graph version frozen with the batch; S6 deferred (documented); S10 honest labels; S11 signed negative controls;
--      S14 R cached per session; S17 FRED prices/FX as levels.
-- Pre-registration integrity: no historic ledger row, frozen weight, frozen path or look schedule is rewritten. The method bump (6.0 → 6.1)
-- is recorded as a model_version ledger row; old frozen hops are re-tested only as new looks (recompute or re-examination rows).
-- Everything stays service-only (RLS on, no grants). Nothing in public.* or the v4/v5 tables is touched.

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Schema additions (additive; nothing dropped)
-- ---------------------------------------------------------------------------------------------------------------------
alter table ripples.att_hop_candidates
  add column if not exists l_by_channel   jsonb,      -- S5: {channel: L} frozen with the batch (template L when the path carries one)
  add column if not exists alt_paths      jsonb,      -- S3: the other paths to the same (node, sign), merged into this candidate at freeze
  add column if not exists engine_version text,       -- method version the batch was frozen under
  add column if not exists graph_version  text;       -- att_build_graph hash in force at freeze (S4)

alter table ripples.att_zvec_ct add column if not exists frac2 real;   -- B4: share of the panel with |z| ≥ 2 on the day

-- B2: the null cache is keyed on the hop's onset month (pre-onset windows only) and may hold a negative result (degenerate / too few windows)
alter table ripples.att_sd_null add column if not exists tp_month date not null default '1900-01-01';
alter table ripples.att_sd_null add column if not exists reason text;
alter table ripples.att_sd_null alter column sd drop not null;
do $$ begin
  if exists (select 1 from pg_constraint where conname = 'att_sd_null_pkey' and conrelid = 'ripples.att_sd_null'::regclass
             and pg_get_constraintdef(oid) = 'PRIMARY KEY (series_id, stat_kind, w_len, sided)') then
    alter table ripples.att_sd_null drop constraint att_sd_null_pkey;
    alter table ripples.att_sd_null add primary key (series_id, stat_kind, w_len, sided, tp_month);
  end if;
end $$;
delete from ripples.att_sd_null;   -- the old whole-array cache is not a valid 6.1 null

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Engine config: method 6.1, graph as-of reads on
-- ---------------------------------------------------------------------------------------------------------------------
update ripples.att_config set value = value || jsonb_build_object('method', '6.1.1', 'graph_asof', true, 'bh_min_draws', 200,
  'method_note', '6.1.1 (2026-09-26): audit fixes B1-B5, S1/S3/S4/S5/S7/S10/S11/S14/S17; BH on the max over placebo families with >= 200 draws (families with >= 30 draws gate through p_h); library BH family = the frozen event group; common-shock panel rule = share of |z| >= 2 in excess of the source panel''s trailing-year median; robust pre-onset null; season-matched placebos on every channel')
 where key = 'engine';

-- S1 (6.1.1): the BH input. A Besag–Clifford p from n draws has resolution 1/(n+1); a family that cannot resolve the Measured threshold
-- (n < bh_min_draws) is a gate (p_h = max over families with ≥ 30 draws, unchanged) but not a BH input — feeding a 60-draw family into
-- BH over hundreds of hops gives q ≥ m/(61·k) for every hop, i.e. Measured unreachable at any effect size. Falls back to p_h when no
-- family resolves.
create or replace function ripples.att_bh_input(p_date real, n_date int, p_topic real, n_topic int, p_link real, n_link int, p_h real, p_min int default 200)
returns real language sql immutable set search_path = '' as $$
  select coalesce(nullif(greatest(coalesce(case when n_date >= p_min then p_date end, 0), coalesce(case when n_topic >= p_min then p_topic end, 0),
                                  coalesce(case when n_link >= p_min then p_link end, 0)), 0), p_h)
$$;
revoke all on function ripples.att_bh_input(real, int, real, int, real, int, real, int) from anon, authenticated, public;

-- S17: FRED price and FX series are levels (ln y), not rates; the series metric already says which is which
update ripples.att_engine_source_map set metric_kinds = coalesce(metric_kinds, '{}'::jsonb) || '{"level":"level","rate":"rate"}'::jsonb where source = 'fred';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Helpers used by the copied engine functions below
-- ---------------------------------------------------------------------------------------------------------------------
-- HISTORY READ POINT: every observation the zvec build reads comes through here. Switch the body to ripples.att_series_daily(...)
-- (the compact multi-year history table) once it exists; attention_obs wins on overlap there.
create or replace function ripples.att_zvec_obs(p_series bigint, p_from date, p_to date) returns table (day date, value float8)
language sql stable set search_path = '' as $$
  select o.day, o.value::float8 from ripples.attention_obs o where o.series_id = p_series and o.day between p_from and p_to
$$;

-- S4: an edge counts for an event only if it was in the graph the day before the onset (config engine.graph_asof; default on)
create or replace function ripples.att_edge_asof(p_valid_from date, p_valid_to date, p_onset date) returns boolean
language sql stable set search_path = '' as $$
  select case when coalesce((ripples._att_cfg('engine') ->> 'graph_asof')::boolean, true)
              then p_valid_from <= p_onset - 1 and (p_valid_to is null or p_valid_to > p_onset - 1)
              else p_valid_to is null end
$$;

-- the mechanism-graph version in force (hash written by att_build_graph's model_version ledger row)
create or replace function ripples.att_graph_version() returns text
language sql stable set search_path = '' as $$
  select ref ->> 'graph_hash' from ripples.att_ledger where kind = 'model_version' and ref ->> 'object' = 'mech_graph' order by seq desc limit 1
$$;

-- S11: the family's typical (modal non-zero) target sign, so negative controls are tested one-sided like the family's real targets
create or replace function ripples.att_family_sign(p_family text) returns int
language sql stable set search_path = '' as $$
  select coalesce((select s from (
           select (x ->> 'sign')::int s from ripples.att_families f, jsonb_array_elements(f.mapper) x where f.family = p_family
           union all select t.sign from ripples.att_mech_templates t where t.family = p_family and t.channel <> 'MONEY') q
         where s <> 0 group by s order by count(*) desc, s desc limit 1), 1)
$$;

-- S5: L for a channel of a hop at freeze: the path's template L when the template targets this channel, else the channel L
create or replace function ripples.att_hop_l(p_channel text, p_template text) returns int
language sql stable set search_path = '' as $$
  select coalesce((select t.l_days::int from ripples.att_mech_templates t where t.template = p_template and t.channel = p_channel and t.l_days is not null),
                  ripples.att_l_days(p_channel))
$$;

-- S5: the frozen L at test time (pre-6.1 hops carry none: the channel prior in force at their freeze applies)
create or replace function ripples.att_hop_l_frozen(p_lbc jsonb, p_channel text) returns int
language sql stable set search_path = '' as $$
  select coalesce((p_lbc ->> p_channel)::int, (select l_days::int from ripples.att_channel_stat where channel = p_channel), 7)
$$;

-- Look schedule (ENGINE §7) for a channel and a (possibly template-specific) L: PHYS +4/+8; BLD/CONS +8/+15; JOBS weekly to L; INST/ECON-monthly
-- monthly to L (a template L ≤ 30 → one look at L + 1); daily channels every day to L
create or replace function ripples.att_look_dates(p_channel text, p_onset date, p_l int) returns date[]
language sql immutable set search_path = '' as $$
  select case
    when p_channel in ('READ','SRCH','SOC','NEWS','TV','PM','ECON') then
      (select array_agg(p_onset + d + 1) from generate_series(1, greatest(p_l, 1)) d)
    when p_channel = 'PHYS' then array[p_onset + 4, p_onset + 8]
    when p_channel in ('BLD','CONS') then array[p_onset + 8, p_onset + 15]
    when p_channel = 'JOBS' then (select array_agg(distinct d order by d) from (select least(p_onset + 7 * k + 1, p_onset + p_l + 1) d from generate_series(1, greatest(1, ceil(p_l / 7.0)::int)) k) x)
    when p_l <= 30 then array[p_onset + p_l + 1]
    else (select array_agg(distinct d order by d) from (select least(p_onset + 30 * k + 1, p_onset + p_l + 1) d from generate_series(1, greatest(1, ceil(p_l / 30.0)::int)) k) x) end
$$;

-- B4: common-shock days = panel rule (≥ 30 % of a ≥ 50-series panel with |z| ≥ 2, or |c_t| ≥ 1.5) ∪ registered days ∪ holidays
-- (US federal holidays ± 1 day, Christmas week, Black Friday). A hop whose onset or window-peak day is listed cannot be Measured.
create or replace function ripples.att_common_days_refresh(p_day date default current_date - 1) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_np int := 0; n_hol int := 0; n_reg int := 0;
begin
  -- panel rule (B4, 6.1.1): a day is a common shock for a source panel when the share of its series with |z| ≥ 2 exceeds the panel's own
  -- trailing-year median share by ≥ 0.30 (a calibrated panel sits near 0.05, so this is the audit's "≥ 30 %" rule; a heavy-tailed panel such
  -- as wiki.pv, whose typical share is 0.32, would otherwise flag every day and switch Measured off), or the panel mean |c| ≥ 1.5
  with b as (select source, coalesce(percentile_cont(0.5) within group (order by frac2), 0) base from ripples.att_zvec_ct
              where day between p_day - 365 and p_day and frac2 is not null group by source),
  c as (select z.day, z.source, z.c, z.frac2, z.n_panel, coalesce(b.base, 0) base from ripples.att_zvec_ct z left join b on b.source = z.source where z.day between p_day - 2555 and p_day),
  f as (select day, array_agg(source order by source) sources,
               jsonb_object_agg(source, round(c::numeric, 3)) || jsonb_build_object('_frac2', jsonb_object_agg(source, round(coalesce(frac2, 0)::numeric, 3)),
                                                                          '_base', jsonb_object_agg(source, round(base::numeric, 3))) cs
        from c where abs(c) >= 1.5 or (coalesce(frac2, 0) - base >= 0.3 and n_panel >= 50) group by day)
  insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
  select day, sources, cs, 'panel', p_day from f
  on conflict (day) do update set sources = excluded.sources, c_by_source = excluded.c_by_source, reason = 'panel', as_of = excluded.as_of;
  get diagnostics v_np = row_count;
  delete from ripples.att_common_days d where d.reason = 'panel' and d.as_of < p_day
     and not exists (select 1 from ripples.att_zvec_ct c left join (select source, coalesce(percentile_cont(0.5) within group (order by frac2), 0) base from ripples.att_zvec_ct
                                                                     where day between p_day - 365 and p_day and frac2 is not null group by source) b on b.source = c.source
                      where c.day = d.day and (abs(c.c) >= 1.5 or (coalesce(c.frac2, 0) - coalesce(b.base, 0) >= 0.3 and c.n_panel >= 50)));
  insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
  select d::date, '{}', '{}'::jsonb, 'registered', p_day
  from jsonb_array_elements_text(coalesce(ripples._att_cfg('common_days'), '[]'::jsonb)) d
  on conflict (day) do update set reason = 'registered';
  get diagnostics n_reg = row_count;
  insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
  select x.d, '{}', jsonb_build_object('holiday', x.code), 'holiday', p_day
  from (select h.day + v.o d, h.code from ripples.att_holidays h cross join (values (-1), (0), (1)) v(o) where h.code like 'us\_%' and h.code <> 'us_blackfriday'
        union select h.day, h.code from ripples.att_holidays h where h.code in ('xmas_week', 'us_blackfriday')) x
  on conflict (day) do nothing;
  get diagnostics n_hol = row_count;
  return jsonb_build_object('day', p_day, 'panel', v_np, 'registered', n_reg, 'holiday_new', n_hol, 'total', (select count(*) from ripples.att_common_days));
end $$;

-- B2: robust null scale of the window statistic. Windows start every day (every 3 days on arrays > 1,000 long) from from + 112, and, when the
-- hop onset is given, END at least L + 30 days before it (no post-onset or future data) and start within the trailing 3 years; PHYS skips the
-- pandemic regime 2020-03-01..2021-06-30. Returns sd = max(1.4826·MAD, floor) with floor 0.5 (peak) / 1.0 (CAR), 'mean' = the median (the
-- centring constant of ž), n, the share of distinct windows; sd is null with a reason when < 20 windows exist or < 20 % of them differ from
-- the median (a dormant / zero-inflated series is not an independent channel).
drop function if exists ripples.att_sd_null_calc(real[], date, int, int, text, int);
create or replace function ripples.att_sd_null_calc(p_ar real[], p_from date, p_n int, p_l int, p_kind text, p_sign int,
                                                    p_tp date default null, p_phys boolean default false) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare t date; s jsonb; v float8; vals float8[] := '{}'; cnt int; rho float8; step int; t_lo date; t_hi date; med float8; mad float8; nz int; fl float8;
begin
  step := case when p_n > 1000 then 3 else 1 end;
  t_lo := p_from + 112; t_hi := p_from + p_n - 1 - p_l;
  if p_tp is not null then
    t_hi := least(t_hi, p_tp - 2 * p_l - 30);
    t_lo := greatest(t_lo, p_tp - 1095);
  end if;
  t := t_lo;
  while t <= t_hi loop
    if p_phys and t + p_l >= '2020-03-01'::date and t <= '2021-06-30'::date then t := t + step; continue; end if;
    rho := case when p_kind = 'car' then ripples.att_rho1(p_ar, p_from, p_n, t) else 0 end;
    s := ripples.att_win_stat(p_ar, null, p_from, p_n, t, p_l, p_kind, p_sign, rho, p_from + p_n - 1, false);
    v := (s ->> 'S')::float8;
    if v is not null and (s ->> 'n')::int >= greatest(1, (p_l + 1) / 2) then vals := vals || v; end if;
    t := t + step;
  end loop;
  cnt := coalesce(cardinality(vals), 0);
  if cnt < 20 then return jsonb_build_object('sd', null, 'n', cnt, 'reason', 'few_windows'); end if;
  select percentile_cont(0.5) within group (order by x) into med from unnest(vals) x;
  select percentile_cont(0.5) within group (order by abs(x - med)), count(*) filter (where abs(x - med) > 1e-6) into mad, nz from unnest(vals) x;
  if nz::float8 / cnt < 0.2 then return jsonb_build_object('sd', null, 'n', cnt, 'reason', 'degenerate', 'nonzero', round((nz::float8 / cnt)::numeric, 3)); end if;
  fl := case when p_kind = 'car' then 1.0 else 0.5 end;
  return jsonb_build_object('sd', greatest(1.4826 * mad, fl), 'mean', med, 'n', cnt, 'nonzero', round((nz::float8 / cnt)::numeric, 3),
                            'mad', 1.4826 * mad, 'floored', 1.4826 * mad < fl, 'from', t_lo, 'to', t_hi);
end $$;

-- B2: null scale for a loaded series at a hop onset (cache att_sd_null keyed on the onset month; negative results cached too). The same
-- constant standardises the real hop and every placebo draw of the hop.
drop function if exists ripples.att_sd_null_get(bigint, text, int, int);
create or replace function ripples.att_sd_null_get(p_series bigint, p_kind text, p_l int, p_sign int, p_tp date default null, p_agg boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v real; m real; j jsonb; b record; v_reason text; v_found boolean := false;
        v_sided text := (case p_sign when 0 then 'abs' when -1 then '-' else '+' end) || case when p_agg then 'a' else '' end;
        v_month date := coalesce(date_trunc('month', p_tp)::date, '1900-01-01'::date);
begin
  select true, sd, mu, reason into v_found, v, m, v_reason from ripples.att_sd_null n
   where n.series_id = p_series and n.stat_kind = p_kind and n.w_len = p_l and n.sided = v_sided and n.tp_month = v_month and n.as_of >= current_date - 7;
  if v_found then
    return case when v is null then jsonb_build_object('sd', null, 'reason', coalesce(v_reason, 'none')) else jsonb_build_object('sd', v, 'mu', m) end;
  end if;
  select * into b from _hb where series_id = p_series;
  if not found then return null; end if;
  j := ripples.att_sd_null_calc(case when p_agg and b.ar_agg is not null then b.ar_agg else b.ar end, b.from_day, b.n, p_l, p_kind, p_sign, p_tp, b.channel = 'PHYS');
  v := (j ->> 'sd')::real; m := coalesce((j ->> 'mean')::real, 0);
  insert into ripples.att_sd_null(series_id, stat_kind, w_len, sided, tp_month, sd, mu, n, as_of, reason)
  values (p_series, p_kind, p_l, v_sided, v_month, v, m, coalesce((j ->> 'n')::int, 0), current_date, j ->> 'reason')
  on conflict (series_id, stat_kind, w_len, sided, tp_month) do update set sd = excluded.sd, mu = excluded.mu, n = excluded.n, as_of = excluded.as_of, reason = excluded.reason;
  return case when v is null then jsonb_build_object('sd', null, 'reason', coalesce(j ->> 'reason', 'none')) else jsonb_build_object('sd', v, 'mu', m) end;
end $$;

-- B5: propagate a parent's retraction / demotion to its children (recursively). A child that was Likely+ is written a new look row
-- (look_no + 100) through the same row shape: retracted with the reason "previous step retracted", or Measured → Likely ("if the previous
-- step holds"). Ledger 'retract' rows are appended; nothing is rewritten. Returns the number of rows written.
create or replace function ripples.att_propagate_parent(p_hop bigint, p_tier text, p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare ch record; lt record; n int := 0; v_new text; v_reason text; v_look int; v_seq bigint; row_j jsonb;
begin
  for ch in select c.hop_id from ripples.att_hop_candidates c where c.parent_hop = p_hop loop
    select * into lt from ripples.att_hop_tests t where t.hop_id = ch.hop_id and t.tier is not null order by t.look_no desc limit 1;
    continue when not found or lt.tier not in ('likely','measured');
    if p_tier not in ('likely','measured') then v_new := 'retracted'; v_reason := 'previous step retracted';
    elsif p_tier = 'likely' and lt.tier = 'measured' then v_new := 'likely'; v_reason := 'if the previous step holds';
    else continue; end if;
    v_look := case when lt.look_no >= 100 then lt.look_no + 1 else lt.look_no + 100 end;
    row_j := to_jsonb(lt) || jsonb_build_object('look_no', v_look, 'tier', v_new, 'tier_reason', v_reason, 'provisional', false,
               'retracted_at', case when v_new = 'retracted' then now() else lt.retracted_at end,
               'retract_reason', case when v_new = 'retracted' then v_reason else lt.retract_reason end,
               'flags', to_jsonb(array_append(coalesce(lt.flags, '{}'), 'parent_' || p_tier)),
               'detail', coalesce(lt.detail, '{}'::jsonb) || jsonb_build_object('propagated_from', p_hop, 'propagated_day', p_as_of, 'prev_tier', lt.tier));
    insert into ripples.att_hop_tests select * from jsonb_populate_record(null::ripples.att_hop_tests, row_j);
    if v_new = 'retracted' then
      v_seq := ripples.att_ledger_append(p_as_of, 'retract', jsonb_build_object('hop_id', ch.hop_id, 'look', v_look, 'propagated_from', p_hop),
                                         jsonb_build_object('hop_id', ch.hop_id, 'reason', v_reason, 'day', p_as_of, 'parent', p_hop, 'parent_tier', p_tier));
      update ripples.att_hop_tests set ledger_seq = v_seq where hop_id = ch.hop_id and look_no = v_look;
    end if;
    update ripples.att_hop_registry g set final_tier = v_new, hit = (v_new in ('likely','measured')) where g.hop_id = ch.hop_id and g.resolved_at is not null;
    n := n + 1 + ripples.att_propagate_parent(ch.hop_id, v_new, p_as_of);
  end loop;
  return n;
end $$;

-- storage: the session bundle cache is emptied at the start of every hop test (topic pools load up to 300 × 2,555-float series per hop)
create or replace function ripples.att_hb_reset() returns void
language plpgsql set search_path = '' as $$
begin
  create temp table if not exists _hb (series_id bigint primary key, source text, channel text, kappa real, quality real, from_day date, n int,
                                       ar real[], resid real[], ar_agg real[], grain text, value_kind text, stat_kind text, l int, attention boolean,
                                       base_level real) on commit drop;
  truncate _hb;
end $$;

-- B1(b) + S7 + history read point: att_zvec_series (copied from 20_att_engine_zvec.sql, edits asserted)
create or replace function ripples.att_zvec_series(p_series bigint, p_day date, p_phi float8 default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s record; v_kind text; v_chan text; v_same boolean; v_n int; v_from date; v_first date; v_last date; v_nobs int;
  v_total bigint; v_agg bigint; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb);
  v_days int := coalesce((cfg->>'zvec_days')::int, 420); v_long int := coalesce((cfg->>'zvec_days_long')::int, 2555);
  v_ar real[]; v_res real[]; v_aragg real[]; v_sigma real; v_b real; v_kappa real; v_base real; v_lam real;
  v_sxy float8; v_sxx float8; v_np int; v_n90 int; v_beta float8; gpool float8[]; hpool jsonb; v_nb_all int; v_minb int; v_sigw int; v_ya boolean := false;
begin
  select se.*, src.grain into s from ripples.att_series se join ripples.att_sources src on src.source = se.source where se.series_id = p_series;
  if not found then return null; end if;
  if s.grain not in ('day','hour') then return null; end if;
  v_kind := ripples.att_series_kind(p_series);
  v_chan := ripples.att_series_channel(p_series);
  select coalesce(m.same_dow, false) into v_same from ripples.att_engine_source_map m where m.source = s.source;
  v_same := coalesce(v_same, false);
  v_minb := case when v_same then 8 else 28 end;   -- same-weekday baselines hold ~13 points; 8 is the floor there
  v_sigw := case when v_same then 371 else 111 end; -- σ window start: same-weekday residuals over a year (≈ 50 points), else B itself
  select min(day), max(day), count(*) into v_first, v_last, v_nobs from ripples.att_zvec_obs(p_series, '1900-01-01', p_day) where value is not null;   -- HISTORY READ POINT
  if v_nobs is null or v_nobs < 28 or v_last < p_day - 60 then return null; end if;
  v_n := least(v_long, greatest(v_days, (p_day - v_first) + 1));   -- B1(b): the array covers the series' history (≤ 7 y)
  v_ya := v_same and v_first <= p_day - 730;   -- S7: same-weekday sources with ≥ 2 prior years get the year-ago-anchored baseline
  v_from := p_day - v_n + 1;
  if v_kind = 'share' and s.key <> '__total__' then
    select series_id into v_total from ripples.att_series t where t.source = s.source and t.metric = s.metric and t.geo = s.geo and t.key = '__total__';
  end if;
  if v_kind = 'share' and s.key = '__total__' then v_kind := 'count'; end if;
  select agg.series_id into v_agg
    from ripples.att_engine_source_map m join ripples.att_series agg on agg.source = s.source and agg.metric = s.metric and agg.key = m.agg_key
    where m.source = s.source and s.key <> m.agg_key limit 1;

  select array_agg(coalesce(w.effect, 0) order by d.dow) into gpool
    from generate_series(0, 6) d(dow) left join ripples.att_weekday w on w.source = s.source and w.geo = 'ALL' and w.dow = d.dow and w.holiday = '';
  select coalesce(jsonb_object_agg(holiday, effect), '{}'::jsonb) into hpool from ripples.att_weekday where source = s.source and geo = 'ALL' and holiday <> '';

  -- days on which the source collected anything (session cache per source): a rank / share series with no row on such a day is
  -- uncharted / zero; on any other day it is simply missing (null), never a zero
  create temp table if not exists _zsd (source text, day date, primary key (source, day)) on commit drop;
  if v_kind in ('rank','share') and not exists (select 1 from _zsd where source = s.source) then
    insert into _zsd select s.source, o.day from ripples.attention_obs o join ripples.att_series x on x.series_id = o.series_id
      where x.source = s.source and o.day >= p_day - v_long - 475 group by o.day on conflict do nothing;
  end if;

  create temp table if not exists _zs (i int, day date, dow int, n float8, x float8, xt float8, m float8, yhat float8, sigma float8,
                                       lam float8, mu float8, var_n float8, nb int, z float8, r float8, h text, primary key (i)) on commit drop;
  truncate _zs;
  -- 1. transform over [from − 475, p_day] (475 = 364 year-ago + 111 baseline); a missing observation is null (ENGINE §3.1)
  insert into _zs(i, day, dow, n, x, h)
  select (g.day::date - v_from + 1), g.day::date, extract(dow from g.day)::int, o.value,
         case v_kind when 'count' then case when o.value is not null then ln(1 + greatest(o.value, 0)) end
                     when 'share' then case when t.value > 0 and (o.value is not null or sd.day is not null) then ln((coalesce(greatest(o.value, 0), 0) + 0.5) / t.value * 1e6) end
                     when 'rank' then case when o.value between 1 and 100 then ln(101 - o.value) when o.value is not null or sd.day is not null then 0 end
                     when 'index' then case when o.value is not null then ln(1 + greatest(o.value, 0)) end
                     when 'level' then case when o.value > 0 then ln(o.value) end
                     else o.value end,
         coalesce(hd.code, '')
  from generate_series(v_from - 475, p_day, interval '1 day') g(day)
  left join ripples.att_zvec_obs(p_series, v_from - 475, p_day) o on o.day = g.day::date                              -- HISTORY READ POINT
  left join ripples.att_zvec_obs(v_total, v_from - 475, p_day) t on v_total is not null and t.day = g.day::date
  left join _zsd sd on v_kind in ('rank','share') and sd.source = s.source and sd.day = g.day::date
  left join ripples.att_holidays hd on hd.day = g.day::date;
  analyze _zs;

  -- 2. weekday (shrunk to pooled, prior weight 8) and holiday adjustment
  with own as materialized (
    select a.dow, count(*) m_k,
           percentile_cont(0.5) within group (order by a.x - (select percentile_cont(0.5) within group (order by b.x) from _zs b
                                                                  where b.i between a.i - 3 and a.i + 3 and b.x is not null)) g_hat
    from _zs a where a.x is not null and a.day > p_day - 365 and a.h = '' group by a.dow),
  gam as materialized (select d.dow, (coalesce(o.m_k, 0) * coalesce(o.g_hat, 0) + 8 * gpool[d.dow + 1]) / (coalesce(o.m_k, 0) + 8) g
          from generate_series(0, 6) d(dow) left join own o on o.dow = d.dow)
  update _zs z set xt = z.x - gam.g - coalesce((hpool ->> z.h)::float8, 0)
  from gam where gam.dow = z.dow and z.x is not null;

  -- 3. year-ago term: r_t = x̃_t − m_t (rolling baseline median; same-weekday for PHYS/ECON); φ̃ applied off holidays only
  update _zs z set r = z.xt - (select percentile_cont(0.5) within group (order by b.xt) from _zs b
                               where b.i between z.i - 111 and z.i - 21 and b.xt is not null and (not v_same or b.dow = z.dow))
  where z.xt is not null and z.i >= -363;
  select coalesce(sum(a.r * b.r), 0), coalesce(sum(b.r * b.r), 0), count(*) into v_sxy, v_sxx, v_np
    from _zs a join _zs b on b.i = a.i - 364
    where a.r is not null and b.r is not null and a.i >= greatest(1, v_n - 1095) and abs(a.r) < 1 and abs(b.r) < 1 and a.h = '' and b.h = '';
  if p_phi <> 0 and v_nobs >= 400 and not v_ya then   -- S7: the anchored baseline replaces the φ year-ago term
    update _zs z set xt = z.xt - p_phi * b.r from _zs b
     where b.i = z.i - 364 and b.r is not null and z.i >= 1 and z.xt is not null and z.h = '' and b.h = '' and abs(b.r) < 1;
  end if;

  -- 4. baseline stats per day t ≥ 1: B = [t−111, t−21] observed (same-weekday for PHYS/ECON); scale floors (ENGINE §3.4)
  update _zs z set m = q.m, lam = q.lam, mu = q.mu_n, var_n = q.var_n, nb = q.nb
  from (
    select a.i,
           percentile_cont(0.5) within group (order by b.xt) m,
           percentile_cont(0.5) within group (order by b.n) lam, avg(b.n) mu_n, var_samp(b.n) var_n, count(*) nb
    from _zs a
    join _zs b on b.i between a.i - 111 and a.i - 21 and b.xt is not null and (not v_same or b.dow = a.dow)
    where a.i >= 1
    group by a.i) q
  where q.i = z.i;
  update _zs set m = null where i >= 1 and coalesce(nb, 0) < v_minb;
  -- S7 (6.1): same-weekday sources with ≥ 2 prior years: baseline = median of the same weekday in the same week of the prior years
  -- (t − 364k ± 7 d, k = 1..3; ≥ 4 points) plus the trailing level offset (median of x̃ − year-ago over [t − 35, t − 21]); the rolling
  -- same-weekday median stays where the prior years are missing. Growth is carried by the level offset, so no trend projection.
  if v_ya then
    create temp table if not exists _zya (i int primary key, ya float8) on commit drop;
    truncate _zya;
    insert into _zya
    select a.i, percentile_cont(0.5) within group (order by b.xt)
    from _zs a join _zs b on b.i in (a.i - 371, a.i - 364, a.i - 357, a.i - 735, a.i - 728, a.i - 721, a.i - 1099, a.i - 1092, a.i - 1085) and b.xt is not null
    where a.i >= -35 group by a.i having count(*) >= 4;
    update _zs z set m = q.ya + q.lvl
    from (select a.i, y.ya, (select percentile_cont(0.5) within group (order by sx.xt - y2.ya) from _zs sx join _zya y2 on y2.i = sx.i
                              where sx.i between a.i - 35 and a.i - 21 and sx.xt is not null) lvl
          from _zs a join _zya y on y.i = a.i where a.i >= 1) q
    where q.i = z.i and q.lvl is not null;
  end if;
  -- σ: 1.4826·MAD of the residuals against the baseline (ENGINE §3.4: B against the day's own median); same-weekday series use a
  -- year of same-weekday residuals, each against its own day's baseline median (inside B: the current median)
  update _zs z set sigma = greatest(
      coalesce((select 1.4826 * percentile_cont(0.5) within group (order by abs(b.xt - case when v_same then coalesce(b.m, z.m) else z.m end)) from _zs b
                where b.i between z.i - v_sigw and z.i - 21 and b.xt is not null and (not v_same or b.dow = z.dow)
                  and (b.i between z.i - 111 and z.i - 21 or b.m is not null)), 0),
      case when v_kind in ('count','share') then greatest(1 / sqrt(coalesce(z.lam, 0) + 1), 0.02)
           when v_kind = 'level' then 0.005 when v_kind = 'rate' then 0.01 else 0.02 end)
  where z.i >= 1 and z.m is not null;

  -- 5. growth: Theil–Sen restricted to same-weekday pairs 5–9 weeks apart inside B, on a weekly grid; applied only if |b|·60 > σ;
  --    needs ≥ 20 pairs from ≥ 40 distinct start days (≥ 8 same-weekday), so a half-empty window never extrapolates
  create temp table if not exists _zsl (i int primary key, b float8) on commit drop;
  truncate _zsl;
  insert into _zsl(i, b)
  select g.i, percentile_cont(0.5) within group (order by (b.xt - a.xt) / d.k)
  from (select i, dow from _zs where i >= 1 and m is not null and (v_n - i) % 7 = 0) g
  join _zs a on a.i between g.i - 111 and g.i - 21 and a.xt is not null and (not v_same or a.dow = g.dow)
  cross join (values (35),(42),(49),(56),(63)) d(k)
  join _zs b on b.i = a.i + d.k and b.i <= g.i - 21 and b.xt is not null
  group by g.i having count(*) >= 20 and count(distinct a.i) >= (case when v_same then 8 else 40 end);
  update _zs z set yhat = case when abs(sl.b) * 60 > z.sigma and not v_ya then z.m + sl.b * 66 else z.m end
  from (select z2.i, (select b from _zsl where _zsl.i <= z2.i order by _zsl.i desc limit 1) b from _zs z2 where z2.i >= 1) sl
  where sl.i = z.i and z.m is not null and sl.b is not null;
  update _zs set yhat = m where i >= 1 and yhat is null and m is not null;
  select b into v_b from _zsl order by i desc limit 1;

  -- 6. z: robust, or NB mid-p when a count source has λ̂ < 10
  update _zs z set z = case
      when z.xt is null or z.yhat is null then null
      when v_kind = 'count' and z.lam < 10 then
        ripples.att_nb_midp_z(z.n, z.mu * exp(z.yhat - z.m),
                              case when z.var_n > z.mu then (z.mu * z.mu) / (z.var_n - z.mu) end)
      else (z.xt - z.yhat) / z.sigma end
  where z.i >= 1;

  -- 7. arrays (index 1 = v_from). ar = raw z for now; panel demeaning (att_zvec_demean) sets ar = raw − c_t.
  select array_agg(z::real order by i), array_agg((xt - yhat)::real order by i)
    into v_ar, v_res from _zs where i >= 1;
  select sigma, lam into v_sigma, v_lam from _zs where i = v_n;
  if v_sigma is null then select sigma, lam into v_sigma, v_lam from _zs where i >= 1 and sigma is not null order by i desc limit 1; end if;
  if v_sigma is null then return null; end if;
  select count(*) into v_n90 from _zs where i > v_n - 90 and x is not null;
  select count(*) into v_nb_all from _zs where i between v_n - 111 and v_n - 21 and xt is not null;
  v_kappa := case when coalesce(v_nb_all, 0) < 28 then 0 else least(1, v_nb_all / 90.0) end;
  select percentile_cont(0.5) within group (order by x) into v_base from _zs where i > v_n - 91 and x is not null;

  -- 8. regional aggregate demeaning: β over the trailing 364 days of z against the aggregate's raw (undemeaned) z
  if v_agg is not null then
    select (sum(a.z * g.z) - count(*) * avg(a.z) * avg(g.z)) / nullif(sum(g.z * g.z) - count(*) * avg(g.z) * avg(g.z), 0)
      into v_beta
      from _zs a join (select zv.from_day + (u.o - 1)::int as day, u.z from ripples.att_zvec zv, unnest(ripples.att_zvec_rawz(zv.series_id)) with ordinality u(z, o) where zv.series_id = v_agg) g
        on g.day = a.day
      where a.i > v_n - 364 and a.z is not null and g.z is not null;
    if v_beta is not null then
      select array_agg((a.z - v_beta * g.z)::real order by a.i) into v_aragg
        from _zs a left join (select zv.from_day + (u.o - 1)::int as day, u.z from ripples.att_zvec zv, unnest(ripples.att_zvec_rawz(zv.series_id)) with ordinality u(z, o) where zv.series_id = v_agg) g
          on g.day = a.day where a.i >= 1;
    end if;
  end if;

  -- ar is written undemeaned (demean 'none' / 'aggregate'); att_zvec_demean subtracts c_t for panel sources afterwards
  insert into ripples.att_zvec(series_id, from_day, grain, n, ar, resid, ar_agg, sigma, trend_b, phi, kappa, demean, agg_series,
                               value_kind, base_level, lam, n_obs, n_obs_90, same_dow, refreshed)
  values (p_series, v_from, 'day', v_n, v_ar, v_res, v_aragg, v_sigma, v_b, p_phi, v_kappa,
          case when v_agg is not null and v_aragg is not null then 'aggregate' else 'none' end, v_agg,
          v_kind, v_base, v_lam, v_nobs, v_n90, v_same, clock_timestamp())
  on conflict (series_id) do update set from_day = excluded.from_day, grain = excluded.grain, n = excluded.n, ar = excluded.ar,
    resid = excluded.resid, ar_agg = excluded.ar_agg, sigma = excluded.sigma, trend_b = excluded.trend_b,
    phi = excluded.phi, kappa = excluded.kappa, demean = excluded.demean, agg_series = excluded.agg_series, value_kind = excluded.value_kind,
    base_level = excluded.base_level, lam = excluded.lam, n_obs = excluded.n_obs, n_obs_90 = excluded.n_obs_90, same_dow = excluded.same_dow,
    refreshed = clock_timestamp();
  return jsonb_build_object('sxy', v_sxy, 'sxx', v_sxx, 'n', v_np, 'nobs', v_nobs);
end $$;

-- B4: panel fraction |z| ≥ 2 per day (att_zvec_demean, one edit)
create or replace function ripples.att_zvec_demean(p_source text, p_day date) returns int
language plpgsql security definer set search_path = '' as $$
declare n_panel int; v_rows int := 0;
begin
  create temp table if not exists _zd (series_id bigint primary key, from_day date, raw real[], in_panel boolean) on commit drop;
  truncate _zd;
  insert into _zd
  select z.series_id, z.from_day, ripples.att_zvec_rawz(z.series_id), coalesce(t.in_panel, false)
  from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id left join ripples.att_topics t on t.topic_id = s.topic_id
  where s.source = p_source and z.grain = 'day';
  select count(*) into n_panel from _zd where in_panel;
  delete from ripples.att_zvec_ct where source = p_source;
  if n_panel < 50 then
    update ripples.att_zvec z set ar = d.raw, demean = 'none' from _zd d where d.series_id = z.series_id and z.demean = 'panel';
    return 0;
  end if;
  insert into ripples.att_zvec_ct(source, day, c, n_panel, frac2)
  select p_source, d.from_day + (u.o - 1)::int, percentile_cont(0.5) within group (order by u.z), count(*), avg((abs(u.z) >= 2)::int)
  from _zd d cross join lateral unnest(d.raw) with ordinality u(z, o)
  where d.in_panel and u.z is not null
  group by 2 having count(*) >= 50;
  update ripples.att_zvec z set ar = q.ar, demean = 'panel'
  from (select d.series_id, array_agg((u.z - coalesce(ct.c, 0))::real order by u.o) ar
        from _zd d cross join lateral unnest(d.raw) with ordinality u(z, o)
        left join ripples.att_zvec_ct ct on ct.source = p_source and ct.day = d.from_day + (u.o - 1)::int
        group by d.series_id) q
  where q.series_id = z.series_id;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

-- B4: att_build_zvec (one block replaced)
create or replace function ripples.att_build_zvec(p_day date default current_date - 1, p_sources text[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; src record; j jsonb; n_ser int := 0; n_src int := 0; v_phi float8; t0 timestamptz := clock_timestamp();
        sxy float8; sxx float8; nser int; npairs int; c_days int := 0;
begin
  for src in
    select s.source, s.grain, coalesce(m.channel, 'READ') channel
    from ripples.att_sources s left join ripples.att_engine_source_map m on m.source = s.source
    where s.enabled and coalesce(m.channel, '') <> 'MONEY'
      and (p_sources is null or s.source = any(p_sources))
      and exists (select 1 from ripples.att_series x where x.source = s.source and x.last_day >= p_day - 60)
    order by 1
  loop
    n_src := n_src + 1;
    if src.grain in ('day','hour') then
      perform ripples.att_zvec_weekday(src.source, p_day);
      sxy := 0; sxx := 0; nser := 0; npairs := 0;
      for r in select series_id from ripples.att_series where source = src.source and key <> '__total__' and last_day >= p_day - 60 loop
        j := ripples.att_zvec_series(r.series_id, p_day, 0);
        if j is not null then
          n_ser := n_ser + 1;
          if (j->>'nobs')::int >= 400 then sxy := sxy + (j->>'sxy')::float8; sxx := sxx + (j->>'sxx')::float8; nser := nser + 1; npairs := npairs + (j->>'n')::int; end if;
        end if;
      end loop;
      v_phi := case when sxx > 0 and npairs >= 200 then least(greatest(sxy / sxx, 0), 1) else 0 end;
      perform ripples.att_state_set('zvec.phi.' || src.source, jsonb_build_object('phi', v_phi, 'series', nser, 'pairs', npairs, 'day', p_day));
      if v_phi <> 0 then
        for r in select z.series_id, z.n_obs from ripples.att_zvec z join ripples.att_series s using (series_id)
                  where s.source = src.source and z.n_obs >= 400 and z.grain = 'day' and s.key <> '__total__' loop
          perform ripples.att_zvec_series(r.series_id, p_day, v_phi * r.n_obs / (r.n_obs + 50.0));
        end loop;
      end if;
      for r in select series_id from ripples.att_series where source = src.source and key = '__total__' and last_day >= p_day - 60 loop
        perform ripples.att_zvec_series(r.series_id, p_day, 0);
      end loop;
      perform ripples.att_zvec_demean(src.source, p_day);
    else
      for r in select series_id from ripples.att_series where source = src.source and last_day >= p_day - 120 loop
        j := ripples.att_zvec_series_periodic(r.series_id, p_day);
        if j is not null then n_ser := n_ser + 1; end if;
      end loop;
    end if;
  end loop;
  c_days := (ripples.att_common_days_refresh(p_day) ->> 'panel')::int;   -- B4: panel rule (≥ 30 % |z| ≥ 2 or |c| ≥ 1.5), holidays, registered days
  return jsonb_build_object('day', p_day, 'sources', n_src, 'series', n_ser, 'common_days', c_days,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- B4: att_build_zvec_step (one block replaced)
create or replace function ripples.att_build_zvec_step(p_day date default current_date - 1, p_budget_s int default 90) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb; t0 timestamptz := clock_timestamp(); j jsonb; n_done int := 0; v_phi float8;
        v_src text; v_stage text; sxy float8; sxx float8; nser int; npairs int; v_sid bigint;
begin
  st := coalesce(ripples.att_state_get('zvec.run'), '{}'::jsonb);
  if (st ->> 'day') is distinct from p_day::text then
    st := jsonb_build_object('day', p_day, 'started', now(), 'sources', (
            select coalesce(jsonb_agg(s.source order by (s.grain in ('day','hour')) desc, s.source), '[]'::jsonb)
            from ripples.att_sources s left join ripples.att_engine_source_map m on m.source = s.source
            where s.enabled and coalesce(m.channel, '') <> 'MONEY'
              and exists (select 1 from ripples.att_series x where x.source = s.source and x.last_day >= p_day - 60)),
          'done', '[]'::jsonb, 'cur', null, 'stage', null, 'pending', '[]'::jsonb, 'sxy', 0, 'sxx', 0, 'nser', 0, 'npairs', 0, 'series', 0);
    perform ripples.att_state_set('zvec.run', st);
  end if;
  if st ? 'finished' then return st - 'sources' - 'pending'; end if;

  while clock_timestamp() - t0 < make_interval(secs => p_budget_s) loop
    v_src := st ->> 'cur';
    if v_src is null then
      select x into v_src from jsonb_array_elements_text(st -> 'sources') x where not (st -> 'done') ? x limit 1;
      if v_src is null then
        perform ripples.att_common_days_refresh(p_day);   -- B4
        st := st || jsonb_build_object('finished', now());
        perform ripples.att_state_set('zvec.run', st);
        return st - 'sources' - 'pending';
      end if;
      select s.grain into v_stage from ripples.att_sources s where s.source = v_src;
      if v_stage in ('day','hour') then
        perform ripples.att_zvec_weekday(v_src, p_day);
        st := st || jsonb_build_object('cur', v_src, 'stage', 'pass1', 'sxy', 0, 'sxx', 0, 'nser', 0, 'npairs', 0,
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and key <> '__total__' and last_day >= p_day - 60));
      else
        st := st || jsonb_build_object('cur', v_src, 'stage', 'periodic',
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and last_day >= p_day - 120));
      end if;
      perform ripples.att_state_set('zvec.run', st);
      continue;
    end if;
    v_stage := st ->> 'stage';
    if jsonb_array_length(st -> 'pending') = 0 then
      if v_stage = 'pass1' then
        sxy := (st ->> 'sxy')::float8; sxx := (st ->> 'sxx')::float8; nser := (st ->> 'nser')::int; npairs := coalesce((st ->> 'npairs')::int, 0);
        v_phi := case when sxx > 0 and npairs >= 200 then least(greatest(sxy / sxx, 0), 1) else 0 end;
        perform ripples.att_state_set('zvec.phi.' || v_src, jsonb_build_object('phi', v_phi, 'series', nser, 'pairs', npairs, 'day', p_day));
        st := st || jsonb_build_object('stage', 'pass2', 'phi', v_phi,
               'pending', case when v_phi <> 0 then (select coalesce(jsonb_agg(z.series_id order by z.series_id), '[]'::jsonb)
                                                     from ripples.att_zvec z join ripples.att_series s using (series_id)
                                                     where s.source = v_src and z.n_obs >= 400 and z.grain = 'day' and s.key <> '__total__') else '[]'::jsonb end);
      elsif v_stage = 'pass2' then
        st := st || jsonb_build_object('stage', 'totals',
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and key = '__total__' and last_day >= p_day - 60));
      elsif v_stage = 'totals' then
        perform ripples.att_zvec_demean(v_src, p_day);
        st := st || jsonb_build_object('cur', null, 'stage', null, 'done', (st -> 'done') || to_jsonb(v_src));
      else
        st := st || jsonb_build_object('cur', null, 'stage', null, 'done', (st -> 'done') || to_jsonb(v_src));
      end if;
      perform ripples.att_state_set('zvec.run', st);
      continue;
    end if;
    v_sid := (st -> 'pending' ->> 0)::bigint;
    if v_stage = 'pass1' then
      j := ripples.att_zvec_series(v_sid, p_day, 0);
      if j is not null then
        st := st || jsonb_build_object('series', (st ->> 'series')::int + 1);
        if (j->>'nobs')::int >= 400 then
          st := st || jsonb_build_object('sxy', (st ->> 'sxy')::float8 + (j->>'sxy')::float8, 'sxx', (st ->> 'sxx')::float8 + (j->>'sxx')::float8,
                                         'nser', (st ->> 'nser')::int + 1, 'npairs', coalesce((st ->> 'npairs')::int, 0) + (j->>'n')::int);
        end if;
      end if;
    elsif v_stage = 'pass2' then
      select n_obs into nser from ripples.att_zvec where series_id = v_sid;
      perform ripples.att_zvec_series(v_sid, p_day, (st ->> 'phi')::float8 * nser / (nser + 50.0));
    elsif v_stage = 'totals' then
      perform ripples.att_zvec_series(v_sid, p_day, 0);
    else
      perform ripples.att_zvec_series_periodic(v_sid, p_day);
    end if;
    st := st || jsonb_build_object('pending', (st -> 'pending') - 0);
    n_done := n_done + 1;
    if n_done % 10 = 0 then perform ripples.att_state_set('zvec.run', st); end if;
  end loop;
  perform ripples.att_state_set('zvec.run', st);
  return jsonb_build_object('day', p_day, 'cur', st ->> 'cur', 'stage', st ->> 'stage', 'done', jsonb_array_length(st -> 'done'),
                            'of', jsonb_array_length(st -> 'sources'), 'series_this_call', n_done, 'pending', jsonb_array_length(st -> 'pending'));
end $$;

-- B4: geo_filter honoured (att_resolve_targets)
create or replace function ripples.att_resolve_targets(p_item jsonb, p_topic bigint) returns setof text
language plpgsql stable set search_path = '' as $$
declare v text; meta jsonb; states text[]; filt text[];
begin
  -- B4: an item with geo_filter is proposed only when the event topic's meta.state intersects it (no state meta → not proposed)
  if p_item ? 'geo_filter' then
    select t.meta into meta from ripples.att_topics t where t.topic_id = p_topic;
    states := array(select regexp_replace(x, '^US-', '') from jsonb_array_elements_text(case when jsonb_typeof(meta -> 'state') = 'array' then meta -> 'state'
                                                                                        when meta ? 'state' then jsonb_build_array(meta ->> 'state') else '[]'::jsonb end) x);
    filt := array(select regexp_replace(x, '^US-', '') from jsonb_array_elements_text(p_item -> 'geo_filter') x);
    if not (coalesce(states, '{}') && coalesce(filt, '{}')) then return; end if;
  end if;
  if p_item ? 'node' then return next p_item ->> 'node'; return; end if;
  if p_item ? 'node_pattern' and p_item ? 'meta_key' then
    select t.meta into meta from ripples.att_topics t where t.topic_id = p_topic;
    if meta is null then return; end if;
    if jsonb_typeof(meta -> (p_item ->> 'meta_key')) = 'array' then
      for v in select x from jsonb_array_elements_text(meta -> (p_item ->> 'meta_key')) x loop
        return next replace(p_item ->> 'node_pattern', '{}', v);
      end loop;
    elsif meta ? (p_item ->> 'meta_key') then
      return next replace(p_item ->> 'node_pattern', '{}', meta ->> (p_item ->> 'meta_key'));
    end if;
    return;
  end if;
  if p_item ? 'source' and p_item ->> 'keys_from' = 'topic_keys' then
    for v in select distinct k.key from ripples.att_keys k where k.topic_id = p_topic and k.source = p_item ->> 'source' and k.enabled loop
      return next (p_item ->> 'source') || ':' || v;
    end loop;
  end if;
  return;
end $$;

-- S4/S5: frozen L + versions in the freeze payload
create or replace function ripples.att_freeze_payload(p_as_of date, p_unfrozen boolean default false, p_hash text default null, p_events bigint[] default null) returns jsonb
language sql stable set search_path = '' as $$
  -- 'method' is the version the BATCH was frozen under (pre-6.1 rows carry none → '6.0'), never the current config: old batches stay bit-identical
  select jsonb_build_object('as_of', p_as_of, 'method', coalesce((select min(c.engine_version) from ripples.att_hop_candidates c where c.as_of = p_as_of and c.engine_version is not null
                                                              and (case when p_unfrozen then c.frozen_hash is null and (p_events is null or c.event_id = any(p_events))
                                                                        when p_hash is not null then c.frozen_hash = p_hash
                                                                        else c.frozen_hash is not null end)), '6.0'),
    'hops', coalesce((select jsonb_agg(jsonb_build_array(c.hop_id, c.event_id, c.role, c.parent_hop, c.depth, c.path, c.path_type, c.node,
                                                        c.prior::float8, c.bh_weight::float8, c.channels, c.excluded_ch, c.window_close, c.looks, c.sign, c.onset)
                                       order by c.hop_id)
                      from ripples.att_hop_candidates c where c.as_of = p_as_of
                        and (case when p_unfrozen then c.frozen_hash is null and (p_events is null or c.event_id = any(p_events))
                                  when p_hash is not null then c.frozen_hash = p_hash
                                  else c.frozen_hash is not null end)),
                     '[]'::jsonb))
  -- engine 6.1 (S4/S5): per-channel frozen L, engine and graph versions and the merged alternative paths are hashed too. The key is
  -- present only when the batch carries them, so every pre-6.1 batch still recomputes bit-identically.
  || coalesce((select jsonb_build_object('frozen_l', jsonb_agg(jsonb_build_array(c.hop_id, c.l_by_channel, c.engine_version, c.graph_version, c.alt_paths) order by c.hop_id))
               from ripples.att_hop_candidates c where c.as_of = p_as_of and c.l_by_channel is not null
                 and (case when p_unfrozen then c.frozen_hash is null and (p_events is null or c.event_id = any(p_events))
                           when p_hash is not null then c.frozen_hash = p_hash
                           else c.frozen_hash is not null end)
               having count(*) > 0), '{}'::jsonb)
$$;

create or replace function ripples.att_freeze_hash(p_as_of date, p_unfrozen boolean default false, p_hash text default null, p_events bigint[] default null) returns text
language sql stable set search_path = '' as $$
  select encode(extensions.digest(ripples._canon(ripples.att_freeze_payload(p_as_of, p_unfrozen, p_hash, p_events))::text, 'sha256'), 'hex')
$$;

-- S4: as-of graph reads (att_gen_candidates, three edits)
create or replace function ripples.att_gen_candidates(p_event bigint, p_as_of date, p_parent_hop bigint default null, p_depth int default 1,
                                                       p_from_node text default null, p_onset date default null) returns int
language plpgsql security definer set search_path = '' as $$
declare e record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); caps jsonb; v_from text; v_topic bigint; v_onset date;
        v_qid text; it jsonb; nd text; n int := 0; r record; v_family text; k int; v_tgt bigint; v_map_from text;
begin
  select * into e from ripples.att_events where event_id = p_event;
  if not found then return 0; end if;
  caps := coalesce(cfg -> 'caps', '{}'::jsonb);
  v_from := coalesce(p_from_node, e.qid);
  v_onset := coalesce(p_onset, e.onset);
  v_family := e.family;
  v_topic := case when v_from ~ '^Q[0-9]+$' then (select topic_id from ripples.att_topics where qid = v_from) when v_from is not null then ripples.att_node_topic(v_from) end;
  if v_topic is null then v_topic := e.topic_id; end if;
  if v_topic is null then return 0; end if;
  v_qid := case when v_from ~ '^Q[0-9]+$' then v_from end;
  -- target resolution (topic keys / meta) goes through the matched real event for decoys: identical candidate generation (ENGINE §1.3).
  -- MAP edges too: a decoy tests the matched real's mapped targets at the decoy's (calm) onset, so every P-MAP cell has decoy coverage.
  v_tgt := coalesce(case when e.role = 'decoy' and e.matched_to is not null then (select topic_id from ripples.att_events where event_id = e.matched_to) end, e.topic_id);
  v_map_from := coalesce(case when e.role = 'decoy' and e.matched_to is not null and p_depth = 1 then (select qid from ripples.att_events where event_id = e.matched_to) end, v_from);

  -- The family mapper and the mechanism library are event-level: they only apply at depth 1. Deeper hops follow edges from the
  -- parent node (MAP / WD / WIKI / co-coverage), never the event's own target list again.
  k := 0;
  for it in select x from ripples.att_families f, jsonb_array_elements(f.mapper) x where f.family = v_family and p_depth = 1 loop
    for nd in select * from ripples.att_resolve_targets(it, v_tgt) loop
      exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(v_from, 'event:' || p_event),'to',nd,'sign',coalesce((it->>'sign')::int,0),'s',1.0,'template',it->>'template','source','family mapper')),
              'P-MAP', coalesce((it->>'sign')::int, 0), null, v_onset, it->>'template', k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;
  for r in select m.to_node, m.sign, m.strength, m.template, m.meta from ripples.att_mech_edges m
            where m.etype = 'MAP' and m.from_node in (coalesce(v_map_from, ''), 'family:' || v_family)
              and (m.from_node like 'family:%' and m.valid_to is null or ripples.att_edge_asof(m.valid_from, m.valid_to, v_onset))   -- S4: graph as of onset − 1
            order by m.strength desc, m.edge_id loop
    exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
    insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
    values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.to_node,
            jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(v_from, 'event:' || p_event),'to',r.to_node,'sign',r.sign,'s',r.strength,'template',r.template,'source','map edge','meta',r.meta)
                              || case when v_map_from is distinct from v_from then jsonb_build_object('via_matched', v_map_from) else '{}'::jsonb end),
            'P-MAP', r.sign, null, v_onset, r.template, k, 0, 1);
    k := k + 1; n := n + 1;
  end loop;

  k := 0;
  for r in select t.* from ripples.att_mech_templates t where t.family = v_family and p_depth = 1 order by t.template loop
    for nd in select * from ripples.att_resolve_targets(r.target_pattern, v_tgt) loop
      exit when k >= coalesce((caps ->> 'P-MECH')::int, 10);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MECH','from',coalesce(v_from, 'event:' || p_event),'to',nd,'sign',r.sign,'s',1.0,'template',r.template,'source','mechanism library v' || r.version,'text',r.rationale)),
              'P-MECH', r.sign, null, v_onset, r.template, k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;

  k := 0;
  if v_qid is not null then
    for r in
      select m.to_node, m.prop, m.strength, exists (select 1 from ripples.att_topics t join ripples.att_series s on s.topic_id = t.topic_id
                                                     join ripples.att_zvec z on z.series_id = s.series_id where t.qid = m.to_node and z.kappa >= 0.3) has_series
      from ripples.att_mech_edges m where m.etype = 'WD' and ripples.att_edge_asof(m.valid_from, m.valid_to, v_onset) and m.from_node = v_qid order by m.strength desc, m.edge_id
    loop
      exit when k >= coalesce((caps ->> 'P-WD')::int, 15);
      if r.has_series then
        insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, rank_in_path, aware, jumps)
        values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.to_node,
                jsonb_build_array(jsonb_build_object('type','WD','from',v_qid,'to',r.to_node,'prop',r.prop,'sign',0,'s',r.strength,'source','Wikidata ' || coalesce(r.prop,''))),
                'P-WD', 0, null, v_onset, k, 0, 0.5);
        k := k + 1; n := n + 1;
      end if;
      for it in select jsonb_build_object('to', m2.to_node, 'sign', m2.sign, 's', m2.strength, 'template', m2.template)
                from ripples.att_mech_edges m2 where m2.etype = 'MAP' and ripples.att_edge_asof(m2.valid_from, m2.valid_to, v_onset) and m2.from_node = r.to_node limit 3 loop
        exit when k >= coalesce((caps ->> 'P-WD')::int, 15);
        insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
        values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, it->>'to',
                jsonb_build_array(jsonb_build_object('type','WD','from',v_qid,'to',r.to_node,'prop',r.prop,'sign',0,'s',r.strength,'source','Wikidata ' || coalesce(r.prop,'')),
                                  jsonb_build_object('type','MAP','from',r.to_node,'to',it->>'to','sign',(it->>'sign')::int,'s',(it->>'s')::real,'template',it->>'template','source','map edge')),
                'P-WD', (it->>'sign')::int, null, v_onset, it->>'template', k, 0, 1);
        k := k + 1; n := n + 1;
      end loop;
    end loop;
  end if;

  k := 0;
  if v_qid is not null then
    for r in
      select c.qid, c.title, c.linked, c.median_views, c.category
      from ripples.candidates c
      where c.root_qid = v_qid and c.depth = 1 and coalesce(c.linked, true)
        and c.as_of = (select max(c3.as_of) from ripples.candidates c3 where c3.root_qid = v_qid and c3.as_of between p_as_of - 2 and p_as_of)   -- the seed day's outlink set
        and coalesce(c.median_views, 0) >= 300 and c.qid <> v_qid
        and not exists (select 1 from ripples.blocklist b where b.qid = c.qid)
        and not exists (select 1 from ripples.articles a where a.qid = c.qid and (a.is_disambig or a.is_list or a.blocked))
      order by coalesce(c.cs_rank, 999), coalesce(c.set_rank, 999), c.median_views desc nulls last
    loop
      exit when k >= coalesce((caps ->> 'P-WIKI')::int, 15);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.qid,
              jsonb_build_array(jsonb_build_object('type','WIKI','from',v_qid,'to',r.qid,'sign',0,'s',1.0,'source','Wikipedia outlink','title',r.title)),
              'P-WIKI', 0, null, v_onset, k, 0.7, 0);
      k := k + 1; n := n + 1;
    end loop;
  end if;

  k := 0;
  for r in
    select ed.source, t.qid, ed.pmi, ed.n, (ed.pmi - st.mu) / nullif(st.sd, 0) pmi_z, ripples.att_series_channel(s0.series_id) ch
    from ripples.att_edges ed
    join ripples.att_topics t on t.topic_id = ed.to_topic and t.qid is not null
    join (select source, avg(pmi) mu, stddev_samp(pmi) sd from ripples.att_edges where period between v_onset - 90 and v_onset - 1 and pmi is not null group by source) st on st.source = ed.source
    left join lateral (select series_id from ripples.att_series s where s.source = ed.source limit 1) s0 on true
    where ed.from_topic = v_topic and ed.period between v_onset - 90 and v_onset - 1 and ed.pmi is not null   -- ENGINE §6: the 90 days before onset, never post-onset co-coverage
      and ripples.att_source_kappa(ed.source) >= 0.3
    order by (ed.pmi - st.mu) / nullif(st.sd, 0) desc nulls last
  loop
    exit when k >= coalesce((caps ->> 'P-COM')::int, 10);
    if r.pmi_z is null or r.pmi_z < 2 then exit; end if;
    insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, excluded_ch, rank_in_path, aware, jumps)
    values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.qid,
            jsonb_build_array(jsonb_build_object('type','GK','from',coalesce(v_from, 'event:' || p_event),'to',r.qid,'sign',0,'s',least(1, r.pmi_z / 5.0),'source','co-coverage ' || r.source,'pmi_z',round(r.pmi_z::numeric,2))),
            'P-COM', 0, null, v_onset, array[r.ch], k, least(1, r.pmi_z / 5.0), 0);
    k := k + 1; n := n + 1;
  end loop;
  -- never re-propose a node this event already tests (any depth) nor the parent node itself (no self-loops)
  if p_depth > 1 then
    delete from ripples.att_cand_stage s
     where s.as_of = p_as_of and s.event_id = p_event and s.parent_hop is not distinct from p_parent_hop and s.depth = p_depth
       and (s.node = v_from or exists (select 1 from ripples.att_hop_candidates c where c.event_id = p_event and c.node = s.node));
    get diagnostics k = row_count; n := n - k;
  end if;
  return n;
end $$;

-- S3/S5/S11/versions: att_freeze_candidates (five edits)
create or replace function ripples.att_freeze_candidates(p_as_of date, p_library boolean default false, p_events bigint[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; r record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); n_stage int := 0; n_ins int := 0; n_new_nodes int := 0;
        v_hash text; v_seq bigint; m int; v_mean float8; v_events int := 0; ch text; v_chs text[]; v_avail text[]; v_l int; v_looks date[];
        v_close date; v_prior float8; v_pi_min float8 := coalesce((cfg->>'pi_min')::float8, 0.05); v_hardcap int := coalesce((cfg->>'hard_cap_tests')::int, 1600);
        v_tchan text; v_h float8; n_neg int := 0; v_frozen_before int; pe jsonb; scope bigint[];
        v_lbc jsonb; v_lc int; v_nsign int; v_gver text := ripples.att_graph_version(); v_ever text := coalesce(ripples._att_cfg('engine') ->> 'method', '6.1');
begin
  -- scope: the events this batch freezes (never one that already has frozen rows)
  if p_events is null then
    select count(*) into v_frozen_before from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is not null and reconstructed = p_library;
    if v_frozen_before > 0 then
      return jsonb_build_object('as_of', p_as_of, 'already_frozen', v_frozen_before,
                                'frozen_hash', (select frozen_hash from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is not null and reconstructed = p_library limit 1));
    end if;
    select coalesce(array_agg(event_id), '{}') into scope from ripples.att_events
     where as_of = p_as_of and role in ('real','decoy','library','positive_control') and coalesce(reconstructed, false) = p_library;
  else
    -- an event may be frozen on several days (depth-1 on its own day, depth-2 children the next morning): one batch per (event, day)
    select coalesce(array_agg(ev.event_id), '{}') into scope from ripples.att_events ev
     where ev.event_id = any(p_events) and coalesce(ev.reconstructed, false) = p_library
       and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = ev.event_id and c.as_of = p_as_of and c.frozen_hash is not null);
    if cardinality(scope) = 0 then return jsonb_build_object('as_of', p_as_of, 'already_frozen', true, 'events', 0); end if;
  end if;
  delete from ripples.att_cand_stage where as_of = p_as_of and depth = 1 and role <> 'fork_check' and event_id = any(scope);

  for e in select * from ripples.att_events where event_id = any(scope) and as_of = p_as_of order by event_id loop   -- depth-1 on the event's own day
    v_events := v_events + 1;
    n_stage := n_stage + ripples.att_gen_candidates(e.event_id, p_as_of);
  end loop;
  select n_stage + count(*) into n_stage from ripples.att_cand_stage where as_of = p_as_of and (depth >= 2 or role = 'fork_check') and event_id = any(scope);

  for e in select * from ripples.att_events where event_id = any(scope) and as_of = p_as_of and role in ('real','library','positive_control') loop
    v_nsign := ripples.att_family_sign(e.family);   -- S11: negatives carry the family's typical sign (like-for-like with the signed decoys)
    for r in select * from ripples.att_negative_pool(e.event_id, p_as_of, 3) as t(node) loop
      insert into ripples.att_cand_stage(as_of, event_id, role, depth, u_topic, node, path, path_type, sign, onset, rank_in_path, aware, jumps)
      values (p_as_of, e.event_id, 'negative_control', 1, coalesce(e.topic_id, ripples.att_node_topic(r.node)), r.node,
              jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(e.qid, 'event:' || e.event_id),'to',r.node,'sign',v_nsign,'s',1.0,'source','negative control')), 'P-NEG', v_nsign, e.onset, n_neg, 0, 1);
      n_neg := n_neg + 1;
    end loop;
  end loop;

  delete from ripples.att_cand_stage s using (
    select ctid, row_number() over (partition by as_of, event_id, parent_hop, node, path_type, role order by rank_in_path) rn
    from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope)) d
  where s.ctid = d.ctid and d.rn > 1;

  for r in select distinct node from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope) loop
    if ripples.att_node_topic(r.node) is null then
      if r.node ~ '^Q[0-9]+$' and n_new_nodes < 60 then
        perform ripples.att_register_topic(r.node, coalesce((select p->>'title' from ripples.att_cand_stage s, jsonb_array_elements(s.path) p
                                                              where s.node = r.node and s.as_of = p_as_of and p ? 'title' limit 1), r.node),
                                            'hop', null, null, 'active', 'en', null, false, '{}'::jsonb);
        n_new_nodes := n_new_nodes + 1;
      elsif r.node ~ '^Q[0-9]+$' then
        insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
        values (r.node, 'unslotted:' || r.node, r.node, 'en', 'dormant', false, 'hop', jsonb_build_object('unslotted', p_as_of))
        on conflict do nothing;
      else
        delete from ripples.att_cand_stage where as_of = p_as_of and node = r.node and event_id = any(scope);
        continue;
      end if;
    end if;
    perform ripples.att_node_bundle(r.node);
  end loop;

  for r in select s.* from ripples.att_cand_stage s where s.as_of = p_as_of and s.event_id = any(scope) order by s.event_id, s.depth, s.path_type, s.rank_in_path loop
    if ripples.att_node_topic(r.node) is null then continue; end if;
    select array_agg(distinct ns.channel order by ns.channel) into v_chs
      from ripples.att_node_series ns where ns.node = r.node and not (ns.channel = any(r.excluded_ch));
    v_chs := coalesce(v_chs, '{}');
    select array_agg(distinct ns.channel) into v_avail
      from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
      where ns.node = r.node and z.kappa >= 0.3 and not (ns.channel = any(r.excluded_ch));
    select ns.channel into v_tchan from ripples.att_node_series ns join ripples.att_channel_stat cs on cs.channel = ns.channel
      where ns.node = r.node and not (ns.channel = any(r.excluded_ch)) order by (cs.kind = 'outcome') desc, ns.channel limit 1;
    v_tchan := coalesce(v_tchan, v_chs[1], 'READ');
    v_prior := 1;
    for pe in select p from jsonb_array_elements(r.path) p loop
      v_prior := v_prior * ripples.att_edge_prior(pe ->> 'type', v_tchan, (select family from ripples.att_events where event_id = r.event_id))
                         * coalesce((pe ->> 's')::float8, 1);
    end loop;
    if r.role = 'negative_control' then v_prior := ripples.att_edge_prior('MAP', v_tchan, 'any'); end if;
    v_looks := '{}'; v_l := 0; v_lbc := '{}'::jsonb;
    foreach ch in array v_chs loop
      v_lc := ripples.att_hop_l(ch, r.template);   -- B3/S5: template L when the path carries one, else the channel L; frozen per channel
      v_lbc := v_lbc || jsonb_build_object(ch, v_lc);
      v_l := greatest(v_l, v_lc);
      v_looks := v_looks || ripples.att_look_dates(ch, r.onset, v_lc);
    end loop;
    if cardinality(v_chs) = 0 then v_l := 7; v_looks := array[r.onset + 8]; end if;
    select array_agg(distinct d order by d) into v_looks from unnest(v_looks) d;
    v_close := r.onset + v_l;
    v_h := (1 - r.aware) * (0.5 + 0.5 * least(1, r.jumps));
    insert into ripples.att_hop_candidates(as_of, u_topic, v_topic, proposed_by, edge, status, event_id, role, parent_hop, depth, path, path_type,
                                           prior, channels, excluded_ch, window_close, looks, voi, node, onset, sign, reconstructed, l_by_channel, engine_version, graph_version)
    values (p_as_of, r.u_topic, ripples.att_node_topic(r.node), array[r.path_type], r.path -> 0,
            case when cardinality(coalesce(v_avail, '{}')) = 0 then 'waiting_series' else 'queued' end,
            r.event_id, r.role, r.parent_hop, r.depth, r.path, r.path_type, v_prior::real, v_chs, r.excluded_ch, v_close, v_looks,
            (v_prior * (1 - v_prior) * (0.5 + 0.5 * v_h))::real, r.node, r.onset, r.sign, p_library, v_lbc, v_ever, v_gver);
    n_ins := n_ins + 1;
  end loop;
  delete from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope);

  -- S3: one candidate per (event, parent, node, sign); the highest-prior path is kept and the others are listed on it as alt_paths
  drop table if exists _dup;
  create temp table _dup on commit drop as
  select hop_id, path, path_type, prior, row_number() over (partition by as_of, event_id, parent_hop, node, sign order by prior desc nulls last, hop_id) rn,
         first_value(hop_id) over (partition by as_of, event_id, parent_hop, node, sign order by prior desc nulls last, hop_id) keep
  from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope) and role <> 'negative_control';
  update ripples.att_hop_candidates c set alt_paths = a.paths
    from (select keep, jsonb_agg(jsonb_build_object('path', path, 'path_type', path_type, 'prior', prior::float8) order by rn) paths from _dup where rn > 1 group by keep) a
   where c.hop_id = a.keep;
  delete from ripples.att_hop_candidates c using _dup d where c.hop_id = d.hop_id and d.rn > 1;
  drop table _dup;
  delete from ripples.att_hop_candidates c using (
    select hop_id, row_number() over (partition by as_of, event_id order by (role = 'negative_control') desc, voi desc, hop_id) rn
    from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope)) d
  where c.hop_id = d.hop_id and d.rn > coalesce((cfg -> 'caps' ->> 'event')::int, 60) + 3;
  select count(*) into m from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  if m > v_hardcap then
    delete from ripples.att_hop_candidates c using (
      select hop_id, row_number() over (order by (path_type in ('P-WIKI','P-COM')) desc, voi asc, hop_id desc) rn
      from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope) and role <> 'negative_control') d
    where c.hop_id = d.hop_id and d.rn <= m - v_hardcap;
  end if;
  update ripples.att_hop_candidates set status = 'skipped' where as_of = p_as_of and frozen_hash is null and event_id = any(scope) and prior < v_pi_min and role <> 'negative_control';

  -- BH weights, frozen before data are read: w = clamp(π / mean π, 0.2, 5), renormalised to Σ w = m over the batch
  select count(*), avg(prior) into m, v_mean from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  if m = 0 then return jsonb_build_object('as_of', p_as_of, 'events', v_events, 'frozen', 0); end if;
  update ripples.att_hop_candidates set bh_weight = least(5, greatest(0.2, prior / nullif(v_mean, 0))) where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  update ripples.att_hop_candidates c set bh_weight = (c.bh_weight * m / s.tot)::real
    from (select sum(bh_weight) tot from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope)) s
   where c.as_of = p_as_of and c.frozen_hash is null and c.event_id = any(scope);

  v_hash := ripples.att_freeze_hash(p_as_of, true, null, scope);
  v_seq := ripples.att_ledger_append(p_as_of, 'freeze', jsonb_build_object('as_of', p_as_of, 'm', m, 'events', v_events, 'library', p_library, 'event_ids', to_jsonb(scope)),
                                     ripples.att_freeze_payload(p_as_of, true, null, scope));
  update ripples.att_hop_candidates set frozen_hash = v_hash, frozen_at = now() where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  for e in select distinct c.event_id from ripples.att_hop_candidates c where c.as_of = p_as_of and c.frozen_hash = v_hash order by 1 loop
    v_seq := ripples.att_ledger_append(p_as_of, 'register', jsonb_build_object('event_id', e.event_id),
      (select coalesce(jsonb_agg(jsonb_build_object('hop_id', c.hop_id, 'window_close', c.window_close, 'p_hat', ripples.att_base_rate(c.hop_id)) order by c.hop_id), '[]'::jsonb)
         from ripples.att_hop_candidates c where c.as_of = p_as_of and c.event_id = e.event_id and c.frozen_hash = v_hash));
    insert into ripples.att_hop_registry(hop_id, window_close, p_hat, family, path_type, channel, ledger_seq)
    select c.hop_id, c.window_close, ripples.att_base_rate(c.hop_id), ev.family, c.path_type, coalesce(c.channels[1], 'none'), v_seq
    from ripples.att_hop_candidates c join ripples.att_events ev on ev.event_id = c.event_id
    where c.as_of = p_as_of and c.event_id = e.event_id and c.frozen_hash = v_hash
    on conflict (hop_id) do nothing;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'events', v_events, 'staged', n_stage, 'frozen', m, 'negative_controls', n_neg,
                            'new_nodes', n_new_nodes, 'frozen_hash', v_hash, 'ledger_seq', v_seq);
end $$;

-- 6.1.1: att_run_library finalizes inside the event group; looks run group-scoped
create or replace function ripples.att_run_library(p_event bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev record; fr jsonb; d date; fin jsonb; last_look date; ex jsonb; fr2 jsonb; fin2 jsonb; last2 date; n_ran int := 0; r jsonb; a date; n_dec int; e2 record; grp bigint[];
begin
  select * into ev from ripples.att_events where event_id = p_event and reconstructed;
  if not found then return jsonb_build_object('error', 'not a reconstructed event'); end if;
  -- an event registered after its day was frozen (library collectors add events with past as_of) is processed on the next unfrozen day
  if exists (select 1 from ripples.att_hop_candidates c where c.as_of = ev.as_of and c.frozen_hash is not null)
     and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = p_event) then
    a := ev.as_of + 1;
    while exists (select 1 from ripples.att_hop_candidates c where c.as_of = a and c.frozen_hash is not null) loop a := a + 1; end loop;
    update ripples.att_events set as_of = a where event_id = p_event;
    ev.as_of := a;
  end if;
  -- decoys for every library event sharing this day (the freeze is per day, so they must exist before it)
  n_dec := 0;
  for e2 in select event_id from ripples.att_events where reconstructed and role in ('library','positive_control') and as_of = ev.as_of loop
    n_dec := n_dec + ripples.att_library_decoys(e2.event_id);
  end loop;
  select array_agg(e.event_id) into grp from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event;
  for a in select distinct e.as_of from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event order by 1 loop
    fr := ripples.att_freeze_candidates(a, true, (select array_agg(e.event_id) from ripples.att_events e where (e.event_id = p_event or e.matched_to = p_event) and e.as_of = a));
  end loop;
  for d in select distinct l from ripples.att_hop_candidates c join ripples.att_events e on e.event_id = c.event_id, unnest(c.looks) l
           where c.reconstructed and (e.event_id = p_event or e.matched_to = p_event) and l <= current_date order by 1 loop
    r := ripples.att_engine_run_group(grp, d);   -- this group only (never another runner's hops)
    n_ran := n_ran + (r ->> 'ran')::int;
    last_look := d;
  end loop;
  fin := case when last_look is not null then ripples.att_finalize(last_look, true, false, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event)) end;   -- BH family = this event group
  if last_look is not null then perform ripples.att_chain_decide(last_look); end if;
  ex := ripples.att_expand(coalesce(last_look, ev.as_of), true);
  if (ex ->> 'children')::int > 0 then
    fr2 := ripples.att_freeze_candidates(coalesce(last_look, ev.as_of) + 1, true, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event));
    for d in select distinct l from ripples.att_hop_candidates c, unnest(c.looks) l where c.as_of = coalesce(last_look, ev.as_of) + 1 and c.reconstructed and l <= current_date order by 1 loop
      r := ripples.att_engine_run_group(grp, d);
      n_ran := n_ran + (r ->> 'ran')::int;
      last2 := d;
    end loop;
    fin2 := case when last2 is not null then ripples.att_finalize(last2, true, false, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event)) end;
    if last2 is not null then perform ripples.att_chain_decide(last2); end if;
  end if;
  perform ripples.att_build_cascade(p_event, coalesce(last2, last_look, ev.as_of));
  return jsonb_build_object('event_id', p_event, 'decoys_created', n_dec, 'freeze', fr - 'frozen_hash', 'looks_ran', n_ran, 'final_day', last_look, 'finalize', fin, 'expand', ex,
                            'depth2', fr2 - 'frozen_hash', 'finalize2', fin2);
end $$;

-- B1: att_library_event with topic meta
drop function if exists ripples.att_library_event(text, text, text, date, text);
create or replace function ripples.att_library_event(p_qid text, p_label text, p_family text, p_onset date, p_role text default 'library', p_meta jsonb default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_topic bigint; v_id bigint; k int; v_slug text; d_topic bigint; d_onset date; kk int;
begin
  if p_qid is not null then
    select topic_id into v_topic from ripples.att_topics where qid = p_qid;
    if v_topic is null then
      v_topic := ripples.att_register_topic(p_qid, p_label, 'cascade', null, null, 'panel', 'en', p_label, false, jsonb_build_object('family', p_family));
    end if;
  else
    insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
    values (null, 'library:' || ripples.att_slugify(p_label) || ':' || p_onset, p_label, 'en', 'panel', false, 'cascade', jsonb_build_object('family', p_family, 'library', true))
    on conflict (label_key) do nothing;
    select topic_id into v_topic from ripples.att_topics where label_key = 'library:' || ripples.att_slugify(p_label) || ':' || p_onset;
  end if;
  -- B1: fixture meta (ba / state / keys) lands on the event topic so the mappers resolve the expected nodes
  if p_meta is not null and v_topic is not null then update ripples.att_topics set meta = coalesce(meta, '{}'::jsonb) || p_meta where topic_id = v_topic; end if;
  select event_id into v_id from ripples.att_events where reconstructed and role = p_role and onset = p_onset and (qid = p_qid or label = p_label);
  if v_id is not null then return v_id; end if;
  v_slug := ripples.att_slugify(p_label) || '-' || to_char(p_onset, 'YYYY');
  if exists (select 1 from ripples.att_events where slug = v_slug) then v_slug := v_slug || '-' || to_char(p_onset, 'MM-DD'); end if;
  insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug, reconstructed)
  values (p_onset, v_topic, p_qid, p_label, p_family, p_role, p_onset, null, false, v_slug, true) returning event_id into v_id;
  perform ripples.att_library_decoys(v_id);
  return v_id;
end $$;

-- S5/S14: att_hb_load (frozen L per channel, R cache)
drop function if exists ripples.att_hb_load(bigint[]);
create or replace function ripples.att_hb_load(p_series bigint[], p_l jsonb default null) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  create temp table if not exists _hb (series_id bigint primary key, source text, channel text, kappa real, quality real, from_day date, n int,
                                       ar real[], resid real[], ar_agg real[], grain text, value_kind text, stat_kind text, l int, attention boolean,
                                       base_level real) on commit drop;
  insert into _hb
  select z.series_id, s.source, ripples.att_series_channel(z.series_id), z.kappa,
         coalesce(src.quality, 1) * 0.5,
         z.from_day, z.n, z.ar, z.resid, z.ar_agg, z.grain, z.value_kind, cs.stat_kind, coalesce((p_l ->> cs.channel)::int, cs.l_days::int), cs.kind = 'attention', z.base_level
  from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id join ripples.att_sources src on src.source = s.source
  join ripples.att_channel_stat cs on cs.channel = ripples.att_series_channel(z.series_id)
  where z.series_id = any(p_series) and cs.channel <> 'MONEY'
  on conflict (series_id) do update set l = excluded.l;   -- S5: the hop's frozen L wins over a value loaded for an earlier hop in the session
  get diagnostics n = row_count;
  -- S14: the shrunk channel correlation is read once per session (att_hop_stat_b used to call att_channel_r for every pair of every draw)
  create temp table if not exists _hr (a text, b text, r float8, primary key (a, b)) on commit drop;
  if not exists (select 1 from _hr) then
    insert into _hr select x.channel, y.channel, ripples.att_channel_r(x.channel, y.channel) from ripples.att_channel_stat x, ripples.att_channel_stat y on conflict do nothing;
  end if;
  return n;
end $$;

-- B2/S14: att_hop_stat_b (null keyed on the hop onset, R cache, degenerate count)
drop function if exists ripples.att_hop_stat_b(jsonb, date, date, int, text[], text, boolean, boolean);
create or replace function ripples.att_hop_stat_b(p_bundle jsonb, p_tp date, p_end date, p_sign int, p_excl text[], p_drop text default null,
                                                  p_agg boolean default false, p_pre boolean default true, p_null_tp date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare it jsonb; b record; st jsonb; pre jsonb; sdj jsonb; sd real; mu real; rho float8; zs float8; zpre float8; ar real[];
        ch jsonb := '{}'::jsonb; c text; cw jsonb; num float8 := 0; den float8 := 0; keys text[]; i int; j int; wi float8;
        t float8; n3 int := 0; n3out int := 0; agree text[] := '{}'; v_onset date := null; v_lag int := null; spre float8 := 0;
        srcs text[] := '{}'; v_kind text; v_l int; v_att boolean; kmin real := null; n_degen int := 0; v_use_agg boolean;
begin
  for it in select x from jsonb_array_elements(p_bundle) x loop
    select * into b from _hb where series_id = (it ->> 'series_id')::bigint;
    continue when not found;
    continue when b.channel = any(coalesce(p_excl, '{}'));
    continue when p_drop is not null and b.source = p_drop;
    continue when coalesce(b.kappa, 0) < 0.3;
    v_kind := b.stat_kind; v_l := b.l; v_att := b.attention;
    ar := case when p_agg and b.ar_agg is not null then b.ar_agg else b.ar end;
    if b.grain in ('week','month') then
      st := ripples.att_release_stat(b.ar, b.resid, b.from_day, b.n, b.grain, p_tp, v_l, p_sign, p_end);
      sd := 1; mu := 0;
      pre := null;
    else
      rho := case when v_kind = 'car' then ripples.att_rho1(ar, b.from_day, b.n, p_tp) else 0 end;
      st := ripples.att_win_stat(ar, b.resid, b.from_day, b.n, p_tp, v_l, v_kind, p_sign, rho, p_end, v_att);
      -- B2: the null scale is a robust, pre-onset scale keyed on the hop's own onset (the same constant standardises the real hop and every draw)
      v_use_agg := p_agg and b.ar_agg is not null;
      sdj := ripples.att_sd_null_get(b.series_id, v_kind, v_l, p_sign, coalesce(p_null_tp, p_tp), v_use_agg);
      sd := (sdj ->> 'sd')::real; mu := coalesce((sdj ->> 'mu')::real, 0);
      if sd is null and sdj ->> 'reason' = 'degenerate' then n_degen := n_degen + 1; end if;
      pre := case when p_pre then ripples.att_win_stat(ar, b.resid, b.from_day, b.n, p_tp - 28, 26, v_kind, p_sign, rho, p_tp - 2, v_att) end;
    end if;
    continue when (st ->> 'S') is null or sd is null or sd <= 0;
    zs := ((st ->> 'S')::float8 - mu) / sd;
    zpre := case when pre is not null and (pre ->> 'S') is not null then ((pre ->> 'S')::float8 - mu) / sd end;
    c := b.channel;
    cw := coalesce(ch -> c, jsonb_build_object('num', 0, 'den', 0, 'kappa', 0, 'n_series', 0, 'zpre', null, 'onset', null, 'sources', '[]'::jsonb, 'S', null, 'sd', null, 'mu', null, 'rho_peak', null, 'stat', v_kind, 'l', v_l));
    wi := coalesce(b.kappa, 0) * coalesce(b.quality, 0.5);
    cw := cw || jsonb_build_object(
      'num', (cw ->> 'num')::float8 + wi * zs, 'den', (cw ->> 'den')::float8 + wi,
      'kappa', greatest((cw ->> 'kappa')::float8, b.kappa), 'n_series', (cw ->> 'n_series')::int + 1,
      'zpre', case when zpre is null then cw -> 'zpre' else to_jsonb(greatest(coalesce((cw ->> 'zpre')::float8, -1e9), zpre)) end,
      'onset', case when (st ->> 'onset') is null then cw -> 'onset'
                    when (cw ->> 'onset') is null then st -> 'onset'
                    else to_jsonb(least((cw ->> 'onset')::date, (st ->> 'onset')::date)) end,
      'sources', (cw -> 'sources') || to_jsonb(b.source),
      'S', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then st -> 'S' else cw -> 'S' end,
      'sd', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then to_jsonb(sd) else cw -> 'sd' end,
      'mu', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then to_jsonb(mu) else cw -> 'mu' end,
      'rho_peak', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then st -> 'rho_peak' else cw -> 'rho_peak' end,
      'peak_day', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then st -> 'peak_day' else cw -> 'peak_day' end,
      'zhat_best', greatest(abs(zs), coalesce((cw ->> 'zhat_best')::float8, 0)),
      'best_series', case when (cw ->> 'S') is null or abs(zs) > abs(coalesce((cw ->> 'zhat_best')::float8, 0)) then to_jsonb(b.series_id) else cw -> 'best_series' end);
    ch := ch || jsonb_build_object(c, cw);
    srcs := srcs || b.source;
    kmin := least(coalesce(kmin, b.kappa), b.kappa);
  end loop;
  if ch = '{}'::jsonb then return jsonb_build_object('T', null, 'channels', '{}'::jsonb, 'n_ch', 0, 'n_degenerate', n_degen); end if;
  -- channel ž_c and weights w_c = max κ; combined T = Σ w ž / √(wᵀRw)
  select array_agg(k order by k) into keys from jsonb_object_keys(ch) k;
  for i in 1..cardinality(keys) loop
    cw := ch -> keys[i];
    zs := (cw ->> 'num')::float8 / nullif((cw ->> 'den')::float8, 0);
    cw := cw || jsonb_build_object('zhat', zs, 'w', (cw ->> 'kappa')::float8);
    cw := cw - 'num' - 'den';
    ch := ch || jsonb_build_object(keys[i], cw);
    num := num + (cw ->> 'w')::float8 * zs;
    if zs >= 3 then
      n3 := n3 + 1; agree := agree || keys[i];
      if (select cs.kind from ripples.att_channel_stat cs where cs.channel = keys[i]) = 'outcome' then n3out := n3out + 1; end if;
      if (cw ->> 'onset') is not null then
        v_onset := least(coalesce(v_onset, (cw ->> 'onset')::date), (cw ->> 'onset')::date);
      end if;
    end if;
    spre := greatest(spre, coalesce((cw ->> 'zpre')::float8, 0));
  end loop;
  for i in 1..cardinality(keys) loop
    for j in 1..cardinality(keys) loop
      den := den + (ch -> keys[i] ->> 'w')::float8 * (ch -> keys[j] ->> 'w')::float8
                 * coalesce((select h.r from _hr h where h.a = keys[i] and h.b = keys[j]), ripples.att_channel_r(keys[i], keys[j]));
    end loop;
  end loop;
  t := case when den > 0 then num / sqrt(den) end;
  if v_onset is not null then v_lag := v_onset - p_tp; end if;
  return jsonb_build_object('T', t, 'channels', ch, 'n_ch', cardinality(keys), 'n_ch3', n3, 'n_out3', n3out, 'agree', to_jsonb(agree),
                            'onset', v_onset, 'lag', v_lag, 's_pre', spre, 'kappa_min', kmin, 'n_degenerate', n_degen,
                            'sources', to_jsonb((select array_agg(distinct s) from unnest(srcs) s)));
end $$;

-- B3: att_date_draws (season matching on all channels)
create or replace function ripples.att_date_draws(p_hop bigint, p_max int) returns date[]
language plpgsql stable security definer set search_path = '' as $$
declare c record; lo date; hi date; hist_from date; n_long int; d date; out date[] := '{}'; season date[] := '{}'; rest date[] := '{}';
        known date[]; v_l int; seas boolean; k int; first_all date; first_any date; ev record; lag_real int; eff date;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  select * into ev from ripples.att_events where event_id = c.event_id;
  -- the pool ends 30 d + L before the hop's OWN onset: a decoy inherits the matched real's as_of − onset lag, applied to its own onset
  lag_real := case when ev.role = 'decoy' and ev.matched_to is not null
                   then (select greatest(0, m.as_of - m.onset) from ripples.att_events m where m.event_id = ev.matched_to)
                   else greatest(0, c.as_of - c.onset) end;
  eff := least(c.as_of, c.onset + coalesce(lag_real, 0));
  select min(z.from_day), count(*) filter (where z.n > 1000) into hist_from, n_long
    from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id where ns.node = c.node and z.grain = 'day';
  v_l := coalesce(c.window_close - c.onset, 7);
  hi := eff - 30 - v_l;
  lo := case when n_long > 0 then greatest(hist_from + 112, eff - 2555) else eff - 730 end;
  -- start where the bundle actually has an abnormal response (young series): every series valid if that leaves ≥ 60 days, else any series
  select max(f), min(f) into first_all, first_any
    from (select z.from_day + (min(u.o) - 1)::int f from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
          cross join lateral unnest(z.ar) with ordinality u(v, o)
          where ns.node = c.node and z.grain = 'day' and u.v is not null group by z.series_id) x;
  if first_all is not null then
    lo := greatest(lo, case when hi - first_all >= 60 then first_all else coalesce(first_any, first_all) end);
  end if;
  seas := true;   -- B3: season-matched draws on every channel (INST/JOBS/BLD/CONS/PM/attention drift with the calendar too)
  -- known onsets (real, library and positive-control events) of the parent topic — through matched_to for a decoy — and of the node
  -- topic are excluded ±30 d (ENGINE §5.1)
  select coalesce(array_agg(distinct e.onset), '{}') into known from ripples.att_events e
   where e.role in ('real','library','positive_control')
     and (e.topic_id in (c.u_topic, c.v_topic) or e.event_id = ev.matched_to
          or (ev.matched_to is not null and e.topic_id = (select m.topic_id from ripples.att_events m where m.event_id = ev.matched_to)));
  d := lo;
  while d <= hi loop
    if not exists (select 1 from unnest(known) kk(x) where abs(d - kk.x) < 30) then
      if seas and exists (select 1 from generate_series(1, 7) y where abs((d + make_interval(years => y))::date - c.onset) <= 21) then
        season := season || d;
      else
        rest := rest || d;
      end if;
    end if;
    d := d + 1;
  end loop;
  out := array[c.onset - 364, c.onset - 371];
  -- season-matched first (≥ 40 % when available), then the rest in a deterministic pseudo-random order (hash of the date)
  select out || coalesce(array_agg(x order by encode(extensions.digest(x::text || p_hop::text, 'sha256'), 'hex')), '{}') into out
    from unnest(season) x where x <> c.onset - 364 and x <> c.onset - 371;
  select coalesce(array_agg(x order by encode(extensions.digest(x::text || p_hop::text, 'sha256'), 'hex')), '{}') into rest
    from unnest(rest) x where x <> c.onset - 364 and x <> c.onset - 371;
  k := 1;
  while cardinality(out) < p_max and k <= cardinality(rest) loop out := out || rest[k]; k := k + 1; end loop;
  return (select array_agg(x order by o) from unnest(out) with ordinality u(x, o) where o <= p_max);
end $$;

-- att_test_hop (frozen L, null keyed on the hop onset)
create or replace function ripples.att_test_hop(p_hop_id bigint, p_look smallint, p_placebo text default null, p_draw int default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; v_end date; v_tp date; bundle jsonb; agg boolean; dd date[]; ll bigint[]; td jsonb; res jsonb; v_look date;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop_id;
  if not found then raise exception 'att_test_hop: unknown hop %', p_hop_id; end if;
  if c.frozen_hash is null then raise exception 'att_test_hop: hop % is not frozen', p_hop_id; end if;
  v_look := c.looks[least(greatest(p_look, 1), cardinality(c.looks))];
  v_end := v_look - 1;
  agg := coalesce(c.path -> 0 -> 'meta' ->> 'demean', '') = 'aggregate';
  bundle := ripples.att_hop_bundle(p_hop_id);
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x), c.l_by_channel);
  v_tp := c.onset;
  if p_placebo is null then
    res := ripples.att_hop_stat_b(bundle, v_tp, v_end, c.sign, c.excluded_ch, null, agg, true, c.onset);
  elsif p_placebo = 'date' then
    dd := ripples.att_date_draws(p_hop_id, greatest(p_draw, 200));
    if p_draw > cardinality(dd) then return null; end if;
    v_tp := dd[p_draw];
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, true, c.onset);
  elsif p_placebo = 'link' then
    ll := ripples.att_link_draws(p_hop_id, 200);
    if p_draw > cardinality(ll) then return null; end if;
    select onset into v_tp from ripples.att_events where event_id = ll[p_draw];
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, true, c.onset);
  elsif p_placebo = 'topic' then
    td := ripples.att_topic_draws(p_hop_id, 300);
    if p_draw > jsonb_array_length(td) then return null; end if;
    perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(td -> (p_draw - 1)) x), c.l_by_channel);
    res := ripples.att_hop_stat_b(td -> (p_draw - 1), v_tp, v_end, c.sign, c.excluded_ch, null, agg, true, c.onset);
  elsif p_placebo = 'rival' then
    select onset into v_tp from ripples.att_events where event_id = p_draw;
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, true, c.onset);
  else
    raise exception 'att_test_hop: bad placebo %', p_placebo;
  end if;
  return coalesce(res, '{}'::jsonb) || jsonb_build_object('hop_id', p_hop_id, 'look', p_look, 'look_day', v_look, 'tp', v_tp, 'placebo', p_placebo, 'draw', p_draw);
end $$;

-- att_run_placebos (frozen L, null keyed on the hop onset)
create or replace function ripples.att_run_placebos(p_hop_id bigint, p_family text, p_max int, p_look smallint default 1, p_t float8 default null,
                                                    p_keep_rows boolean default false, p_gate boolean default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); bc int := coalesce((cfg ->> 'bc_stop')::int, 10);
        t_h float8 := p_t; v_end date; bundle jsonb; agg boolean; dd date[]; ll bigint[]; td jsonb; n_draw int; i int; res jsonb; tp date;
        exceed int := 0; n_done int := 0; p float8; gates boolean; stopped boolean := false; tv float8; ids bigint[]; gate boolean := p_gate;
        ts real[] := '{}'; n_gated int := 0;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop_id;
  v_end := c.looks[least(greatest(p_look, 1), cardinality(c.looks))] - 1;
  agg := coalesce(c.path -> 0 -> 'meta' ->> 'demean', '') = 'aggregate';
  bundle := ripples.att_hop_bundle(p_hop_id);
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x), c.l_by_channel);
  if t_h is null or gate is null then
    res := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, null, agg, true, c.onset);
    t_h := coalesce(t_h, (res ->> 'T')::float8);
    gate := coalesce(gate, coalesce((res ->> 's_pre')::float8, 0) < 2);
  end if;
  if t_h is null then return jsonb_build_object('family', p_family, 'n', 0, 'p', null, 'reason', 'no statistic'); end if;
  if p_family = 'date' then dd := ripples.att_date_draws(p_hop_id, p_max); n_draw := cardinality(dd);
  elsif p_family = 'link' then ll := ripples.att_link_draws(p_hop_id, p_max); n_draw := cardinality(ll);
  elsif p_family = 'topic' then
    td := ripples.att_topic_draws(p_hop_id, p_max); n_draw := jsonb_array_length(td);
    select array_agg(distinct (x ->> 'series_id')::bigint) into ids from jsonb_array_elements(td) d, jsonb_array_elements(d) x;
    if ids is not null then perform ripples.att_hb_load(ids, c.l_by_channel); end if;
  else raise exception 'att_run_placebos: bad family %', p_family; end if;
  for i in 1..n_draw loop
    if p_family = 'date' then
      tp := dd[i];
      res := ripples.att_hop_stat_b(bundle, tp, tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, true, c.onset);
    elsif p_family = 'link' then
      select onset into tp from ripples.att_events where event_id = ll[i];
      res := ripples.att_hop_stat_b(bundle, tp, tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, true, c.onset);
    else
      res := ripples.att_hop_stat_b(td -> (i - 1), c.onset, v_end, c.sign, c.excluded_ch, null, agg, true, c.onset);
    end if;
    tv := (res ->> 'T')::float8;
    continue when tv is null;
    gates := (not gate) or coalesce((res ->> 's_pre')::float8, 0) < 2;
    if p_keep_rows then ts := ts || (case when gates then tv else -tv - 1000 end)::real; end if;   -- gated-out draws stored negative-offset
    if not gates then n_gated := n_gated + 1; continue; end if;   -- outside the conditional null (already moving): neither a draw nor an exceedance
    n_done := n_done + 1;
    if tv >= t_h then exceed := exceed + 1; end if;
    if exceed >= bc and n_done >= 30 and not p_keep_rows then stopped := true; exit; end if;   -- ≥ 30 draws before stopping: p keeps ≥ 1/31 resolution and no family is lost to an early stop
  end loop;
  if p_keep_rows and n_done > 0 then
    insert into ripples.att_placebo_top(hop_id, look_no, kind, as_of, t_h, n, exceed, gated, t_stats)
    values (p_hop_id, p_look, p_family, c.as_of, t_h, n_done, exceed, gate, ts)
    on conflict (hop_id, look_no, kind) do update set t_h = excluded.t_h, n = excluded.n, exceed = excluded.exceed, gated = excluded.gated,
      t_stats = excluded.t_stats, as_of = excluded.as_of, created_at = now();
  end if;
  -- Besag–Clifford: p = h/l when the loop stopped at the h-th exceedance; a stop at the 30-draw floor with more exceedances is a fixed-n estimate
  p := case when n_done = 0 then null when stopped and exceed = bc then bc::float8 / n_done else (1 + exceed)::float8 / (1 + n_done) end;
  return jsonb_build_object('family', p_family, 'n', n_done, 'available', n_draw, 'exceed', exceed, 'p', p, 'stopped', stopped, 't_h', t_h, 'gated', gate, 'n_gated', n_gated);
end $$;

-- B3/B4/B5: att_engine_job (young-series flag, peak-day common shock, re-exam rows, frozen L)
create or replace function ripples.att_engine_job(p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_hop bigint := (p_args ->> 'hop_id')::bigint; v_look smallint := coalesce((p_args ->> 'look')::smallint, 1);
        c record; ev record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); real_r jsonb; t_h float8; v_end date; v_look_day date;
        pd jsonb; pl jsonb; pt jsonb; p_h float8; n_fam int := 0; fams jsonb := '{}'::jsonb; is_final boolean; link text; att_only boolean;
        cs boolean; rev jsonb; loso boolean := null; src text; r2 jsonb; attrib jsonb; rivals jsonb := '[]'::jsonb; lr_u float8; lr_sum float8; e record;
        agg boolean; bundle jsonb; v_onset date; v_lag int; lag_ok boolean; n_ch3 int; n_out3 int; floor_p float8; flags text[] := '{}';
        min_draws int := coalesce((cfg ->> 'min_family_draws')::int, 30); gate boolean; v_store smallint; first_ar date; v_reexam date;
begin
  select * into c from ripples.att_hop_candidates where hop_id = v_hop;
  if not found or c.frozen_hash is null then return jsonb_build_object('skipped', 'not frozen'); end if;
  select * into ev from ripples.att_events where event_id = c.event_id;
  if v_look > cardinality(c.looks) then v_look := cardinality(c.looks); end if;
  v_look_day := c.looks[v_look]; v_end := v_look_day - 1; is_final := v_look = cardinality(c.looks);
  -- B5: a re-examination recomputes the frozen final look on today's arrays and stores it as look_no ≥ 100 (the original row is never rewritten)
  v_store := coalesce((p_args ->> 'store_look')::smallint, v_look); v_reexam := (p_args ->> 'reexam_day')::date;
  agg := coalesce(c.path -> 0 -> 'meta' ->> 'demean', '') = 'aggregate';
  -- MONEY never tests; IO never proposes (no IO candidates exist); waiting_series has no statistic yet
  if exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel = 'MONEY') and
     not exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel <> 'MONEY') then
    return jsonb_build_object('skipped', 'MONEY channel is disabled');
  end if;
  perform ripples.att_hb_reset();   -- storage: one hop's series at a time in the session cache
  bundle := ripples.att_hop_bundle(v_hop);
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x), c.l_by_channel);
  real_r := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, null, agg, true, c.onset);
  t_h := (real_r ->> 'T')::float8;
  if t_h is null then
    update ripples.att_hop_candidates set status = 'waiting_series' where hop_id = v_hop and status in ('queued','testing');
    insert into ripples.att_hop_tests(hop_id, look_no, as_of, u_topic, v_topic, t_u, look_day, is_final, tier, tier_reason, s_by_channel, flags)
    values (v_hop, v_store, c.as_of, c.u_topic, c.v_topic, c.onset, v_look_day, is_final, 'watching', 'waiting_series', real_r -> 'channels', array['waiting_series'])
    on conflict (hop_id, look_no) do update set look_day = excluded.look_day, tier = 'watching', tier_reason = 'waiting_series', flags = excluded.flags;
    return jsonb_build_object('hop_id', v_hop, 'look', v_look, 'status', 'waiting_series');
  end if;
  update ripples.att_hop_candidates set status = 'testing' where hop_id = v_hop and status in ('queued','waiting_series');

  -- three placebo families through the identical code path; draws are gated on S_pre only when the real hop passes that gate
  gate := coalesce((real_r ->> 's_pre')::float8, 0) < 2;
  pd := ripples.att_run_placebos(v_hop, 'date', coalesce((cfg ->> 'date_draws')::int, 200), v_look, t_h, false, gate);
  pl := ripples.att_run_placebos(v_hop, 'link', coalesce((cfg ->> 'link_draws')::int, 200), v_look, t_h, false, gate);
  pt := ripples.att_run_placebos(v_hop, 'topic', coalesce((cfg ->> 'topic_draws')::int, 300), v_look, t_h, false, gate);
  p_h := null; floor_p := null;
  foreach src in array array['date','link','topic'] loop
    r2 := case src when 'date' then pd when 'link' then pl else pt end;
    if (r2 ->> 'n')::int >= min_draws and (r2 ->> 'p') is not null then
      n_fam := n_fam + 1;
      p_h := greatest(coalesce(p_h, 0), (r2 ->> 'p')::float8);
      floor_p := greatest(coalesce(floor_p, 0), 1.0 / (1 + (r2 ->> 'n')::int));
    end if;
    fams := fams || jsonb_build_object(src, r2 - 't_h');
  end loop;

  -- linkage kind (ENGINE §3.9): from the frozen path; comention counts only from a source not in C
  link := case (c.path -> 0 ->> 'type') when 'MECH' then 'mechanism' when 'MAP' then 'mechanism' when 'CS' then 'measured'
               when 'GK' then 'comention' when 'WIKI' then 'structural' when 'WD' then 'structural' else 'none' end;
  if c.role = 'negative_control' then link := 'none'; end if;
  n_ch3 := coalesce((real_r ->> 'n_ch3')::int, 0); n_out3 := coalesce((real_r ->> 'n_out3')::int, 0);
  att_only := n_ch3 > 0 and n_out3 = 0;
  v_onset := (real_r ->> 'onset')::date; v_lag := (real_r ->> 'lag')::int;
  -- B4: the onset day OR the window's peak day (of any channel with ž ≥ 3) on a common-shock / holiday day flags the hop
  cs := exists (select 1 from ripples.att_common_days d where d.day = coalesce(v_onset, c.onset))
        or exists (select 1 from jsonb_each(real_r -> 'channels') e(k, v) join ripples.att_common_days d on d.day = (v ->> 'peak_day')::date where (v ->> 'zhat')::float8 >= 3);
  rev := ripples.att_lag_reversed(v_hop, v_end);
  lag_ok := (v_lag is null or v_lag >= 0) and not coalesce((rev ->> 'reversed')::boolean, false);
  if v_lag is not null and v_lag < 0 then flags := array_append(flags, 'lag_negative'); end if;
  if coalesce((rev ->> 'reversed')::boolean, false) then flags := array_append(flags, 'reversed'); end if;
  if cs then flags := array_append(flags, 'common_shock'); end if;
  if coalesce((real_r ->> 's_pre')::float8, 0) >= 2 then flags := array_append(flags, 'already_moving'); end if;
  if att_only then flags := array_append(flags, 'attention_ripple'); end if;
  if link = 'structural' then flags := array_append(flags, 'linkage_structural'); end if;
  if n_fam < 2 then flags := array_append(flags, 'few_placebo_families'); end if;
  -- B3: fewer than two prior years of abnormal response in the bundle → the season cannot be matched → capped at Likely
  select min(z.from_day + (u.o - 1)::int) into first_ar from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
    cross join lateral (select min(o) o from unnest(z.ar) with ordinality u(v, o) where u.v is not null) u
   where ns.node = c.node and z.grain = 'day' and z.kappa >= 0.3 and not (ns.channel = any(coalesce(c.excluded_ch, '{}')));
  if first_ar is null or first_ar > c.onset - 730 then flags := array_append(flags, 'young_series'); end if;
  if coalesce((real_r ->> 'n_degenerate')::int, 0) > 0 then flags := array_append(flags, 'degenerate_series_excluded'); end if;
  if v_reexam is not null then flags := array_append(flags, 'reexam'); end if;

  -- LOSO: with ≥ 2 contributing sources, every T_{−s} ≥ 3
  if jsonb_array_length(coalesce(real_r -> 'sources', '[]'::jsonb)) >= 2 then
    loso := true;
    for src in select x from jsonb_array_elements_text(real_r -> 'sources') x loop
      r2 := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, src, agg, false, c.onset);
      if coalesce((r2 ->> 'T')::float8, 0) < coalesce((cfg ->> 'loso_min_t')::float8, 3) then loso := false; end if;
    end loop;
  end if;

  -- attribution share against concurrent real rivals with a registered path to the same node (ENGINE §3.11)
  lr_u := exp(3 * t_h - 4.5); lr_sum := lr_u;
  for e in select distinct e2.event_id, e2.label, e2.onset from ripples.att_events e2 join ripples.att_hop_candidates c2 on c2.event_id = e2.event_id
            where e2.role = 'real' and e2.event_id <> c.event_id and c2.node = c.node and c2.frozen_hash is not null and not e2.reconstructed
              and abs(e2.onset - c.onset) <= coalesce(c.window_close - c.onset, 7) loop
    r2 := ripples.att_hop_stat_b(bundle, e.onset, e.onset + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, false, c.onset);
    if (r2 ->> 'T') is not null then
      lr_sum := lr_sum + exp(3 * (r2 ->> 'T')::float8 - 4.5);
      rivals := rivals || jsonb_build_object('event_id', e.event_id, 'label', e.label, 'lr', exp(3 * (r2 ->> 'T')::float8 - 4.5), 't', (r2 ->> 'T')::float8);
    end if;
  end loop;
  attrib := jsonb_build_object('share', lr_u / lr_sum, 'rivals', rivals);
  if lr_u / lr_sum < 0.5 then flags := array_append(flags, 'rival'); end if;

  insert into ripples.att_hop_tests(hop_id, look_no, as_of, u_topic, v_topic, t_u, t_v, lag_days, onsets, t_stat, n_channels_3, ratio,
                                    link_kind, p_topic, n_topic, p_date, n_date, p_link, n_link, fluke, detail,
                                    look_day, is_final, stat_kind, s_by_channel, s_pre, common_shock, attribution, loso_ok, linkage,
                                    n_families, attention_only, reversed, lag_ok, p_floor, placebo, flags, rho_raw)
  values (v_hop, v_store, c.as_of, c.u_topic, c.v_topic, c.onset, v_onset, v_lag,
          (select jsonb_object_agg(k, v -> 'onset') from jsonb_each(real_r -> 'channels') e(k, v)), t_h, n_ch3, null,
          link, (pt ->> 'p')::real, (pt ->> 'n')::int, (pd ->> 'p')::real, (pd ->> 'n')::int, (pl ->> 'p')::real, (pl ->> 'n')::int, p_h,
          jsonb_build_object('agree', real_r -> 'agree', 'n_out3', n_out3, 'sources', real_r -> 'sources', 'lag_check', rev, 'kappa_min', real_r -> 'kappa_min',
                             'engine_version', coalesce(cfg ->> 'method', '6.1'), 'reexam_day', v_reexam, 'first_ar', first_ar,
                             'lag_days', v_lag, 'lag_from_event_days', case when v_onset is not null then v_onset - ev.onset end),
          v_look_day, is_final, (select string_agg(distinct v ->> 'stat', ',') from jsonb_each(real_r -> 'channels') e(k, v)),
          real_r -> 'channels', (real_r ->> 's_pre')::real, cs, attrib, loso,
          jsonb_build_object('kind', link, 'source', c.path -> 0 ->> 'source'), n_fam, att_only, coalesce((rev ->> 'reversed')::boolean, false), lag_ok,
          floor_p, fams, flags,
          (select max((v ->> 'rho_peak')::real) from jsonb_each(real_r -> 'channels') e(k, v) where (v ->> 'zhat')::float8 >= 3))
  on conflict (hop_id, look_no) do update set
    t_v = excluded.t_v, lag_days = excluded.lag_days, onsets = excluded.onsets, t_stat = excluded.t_stat, n_channels_3 = excluded.n_channels_3,
    link_kind = excluded.link_kind, p_topic = excluded.p_topic, n_topic = excluded.n_topic, p_date = excluded.p_date, n_date = excluded.n_date,
    p_link = excluded.p_link, n_link = excluded.n_link, fluke = excluded.fluke, detail = excluded.detail, look_day = excluded.look_day,
    is_final = excluded.is_final, stat_kind = excluded.stat_kind, s_by_channel = excluded.s_by_channel, s_pre = excluded.s_pre,
    common_shock = excluded.common_shock, attribution = excluded.attribution, loso_ok = excluded.loso_ok, linkage = excluded.linkage,
    n_families = excluded.n_families, attention_only = excluded.attention_only, reversed = excluded.reversed, lag_ok = excluded.lag_ok,
    p_floor = excluded.p_floor, placebo = excluded.placebo, flags = excluded.flags, rho_raw = excluded.rho_raw;
  -- ENGINE §4.3–4.4 (6.1.2): the chaining record for a child hop (order / fork test / mediation c) — the story layer's chain edge reads it
  if c.depth >= 2 then
    update ripples.att_hop_tests t set detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('chain', ripples.att_chain_check(v_hop, v_store)) where t.hop_id = v_hop and t.look_no = v_store;
  end if;
  update ripples.att_hop_candidates set status = 'tested' where hop_id = v_hop;
  return jsonb_build_object('hop_id', v_hop, 'look', v_look, 'store_look', v_store, 'T', t_h, 'p', p_h, 'families', n_fam, 'flags', to_jsonb(flags));
end $$;

-- S1/B3/B5/S5/S10: att_finalize
drop function if exists ripples.att_finalize(date, boolean);
drop function if exists ripples.att_finalize(date, boolean, boolean);
create or replace function ripples.att_finalize(p_as_of date, p_library boolean default false, p_reexam boolean default false, p_events bigint[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb);
        q_meas float8 := coalesce((cfg ->> 'q_measured')::float8, 0.05); q_lik float8 := coalesce((cfg ->> 'q_likely')::float8, 0.20);
        q_prov float8 := coalesce((cfg ->> 'q_provisional')::float8, 0.01); q_dem float8 := coalesce((cfg ->> 'q_demote')::float8, 0.10);
        top_n int := coalesce((cfg ->> 'top_n')::int, 100); top_draws int := coalesce((cfg ->> 'date_draws_top')::int, 2000);
        r record; m int; ext jsonb; fb jsonb; warming boolean; v_tier text; v_reason text; fails text[];
        prev_tier text; pub_tier text; fam text; v_kappa_min float8; longest_final date; ch text; v_agree text[]; v_final_agree boolean;
        n_meas int := 0; n_lik int := 0; n_flat int := 0; n_watch int := 0; n_retract int := 0; v_seq bigint;
        rho jsonb; best jsonb; z record; v_ch text; fj jsonb; v_broken boolean; v_prov boolean; cs boolean; v_parent_tier text; tiers jsonb;
        gate_lik boolean; v_at_final boolean;
        sum_f float8 := 0; sum_p float8 := 0; n_tested int := 0; n_moved int := 0; frozen jsonb; e record; sbc jsonb;
        prev_prov boolean; v_lbc jsonb; fam_p float8[]; fam_w float8[]; fam_q float8[]; fam_ids bigint[]; fam_i int; v_orig record;
        v_bhmin int := coalesce((cfg ->> 'bh_min_draws')::int, 200);
begin
  -- the day's family: every hop's latest look with a statistic that is not yet finalised, or that looked today
  drop table if exists _fin; drop table if exists _bh; drop table if exists _q; drop table if exists _nf;
  create temp table _fin on commit drop as
  select t.hop_id, t.look_no, t.t_stat, t.fluke p_h, t.p_date, t.n_date, t.s_pre, c.bh_weight, c.role, c.event_id, c.depth, c.parent_hop, c.path_type, c.channels, c.window_close, c.looks,
         t.is_final, t.look_day, c.prior,
         -- S1 (engine 6.1.1): BH runs on the max over the placebo families that RESOLVE the threshold (≥ bh_min_draws = 200 draws, floor ≤ 0.005);
         -- every family with ≥ 30 draws stays a hard gate through p_h (a 60-draw family cannot certify below 1/61 and would only cap q)
         ripples.att_bh_input(t.p_date, t.n_date, t.p_topic, t.n_topic, t.p_link, t.n_link, t.fluke, v_bhmin) p_bh
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.t_stat is not null and t.fluke is not null and c.frozen_hash is not null and c.reconstructed = p_library and t.look_day <= p_as_of
    -- B5: re-examination rows (look_no ≥ 100) form their own run; the daily run never sees them
    and (case when p_reexam then t.look_no >= 100 and t.q_w is null and (t.detail ->> 'reexam_day')::date = p_as_of else t.look_no < 100 end)
    and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = t.hop_id and t2.t_stat is not null and t2.look_day <= p_as_of
                                and (case when p_reexam then t2.look_no >= 100 else t2.look_no < 100 end))
    and (p_reexam or t.q_w is null or t.look_day = p_as_of or exists (select 1 from ripples.att_hop_candidates c2 where c2.hop_id = c.hop_id and c2.as_of = p_as_of))
    -- library mode: the BH family is the event group (the event, its decoys and negatives, frozen together with weights summing to m);
    -- unfinalised looks of other groups in a concurrent recompute never join it
    and (p_events is null or c.event_id = any(p_events));
  select count(*) into m from _fin;

  -- looks with a statistic but no placebo family of ≥ 30 draws carry no p-value: they never enter BH and resolve as watching (interim)
  -- or flat (final) with the reason named; they still count in the day's denominators (p taken as 1, the conservative reading)
  drop table if exists _nf;
  create temp table _nf on commit drop as
  select t.hop_id, t.look_no, t.is_final, t.look_day, c.window_close, c.event_id
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.t_stat is not null and t.fluke is null and t.tier is null and c.frozen_hash is not null and c.reconstructed = p_library and t.look_day <= p_as_of
    and (case when p_reexam then t.look_no >= 100 else t.look_no < 100 end)
    and (p_events is null or c.event_id = any(p_events));
  for r in select * from _nf loop
    v_tier := case when r.is_final or r.look_day >= r.window_close + 1 then 'flat' else 'watching' end;
    update ripples.att_hop_tests t set tier = v_tier, tier_reason = 'too few placebo draws',
           detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('fails', to_jsonb(array['placebo families']))
     where t.hop_id = r.hop_id and t.look_no = r.look_no;
    n_tested := n_tested + 1; sum_p := sum_p + 1;
    if v_tier = 'flat' then n_flat := n_flat + 1; else n_watch := n_watch + 1; end if;
    if r.is_final then
      update ripples.att_hop_registry g set resolved_at = coalesce(g.resolved_at, now()), hit = false, final_tier = v_tier where g.hop_id = r.hop_id;
      update ripples.att_hop_candidates set status = 'tested' where hop_id = r.hop_id;
    end if;
  end loop;

  if m = 0 then
    perform ripples.att_fluke_bins_refresh(p_as_of);
    for e in select distinct event_id from _nf loop
      perform ripples.att_event_status(e.event_id, p_as_of);
      perform ripples.att_build_cascade(e.event_id, p_as_of);
    end loop;
    return jsonb_build_object('as_of', p_as_of, 'tested', n_tested, 'moved', 0, 'measured', 0, 'flat', n_flat, 'watching', n_watch, 'note', 'no looks with a p-value to finalise');
  end if;

  -- top-100 by T (only hops that can still matter: date p ≤ 0.05): extend the date family to 2,000 draws (compact rows, 7-day retention)
  for r in select hop_id, look_no, t_stat, s_pre from _fin where p_bh <= 0.05 order by t_stat desc nulls last limit top_n loop
    -- T_h and the pre-trend gate are recomputed in float8 through the identical code path (the stored t_stat is float4: the hop's own
    -- shift-0 draw could round below it and not count as an exceedance)
    ext := ripples.att_run_placebos(r.hop_id, 'date', top_draws, r.look_no, null, true, null);
    if (ext ->> 'n')::int >= 30 then
      update ripples.att_hop_tests t set p_date = (ext ->> 'p')::real, n_date = (ext ->> 'n')::int,
             placebo = coalesce(t.placebo, '{}'::jsonb) || jsonb_build_object('date', ext - 't_h'),
             fluke = greatest(coalesce(case when n_link >= 30 then p_link end, 0), coalesce(case when n_topic >= 30 then p_topic end, 0), (ext ->> 'p')::real),
             p_floor = least(coalesce(p_floor, 1), 1.0 / (1 + (ext ->> 'n')::int))
       where t.hop_id = r.hop_id and t.look_no = r.look_no;
      update _fin f set p_h = t.fluke, p_bh = ripples.att_bh_input(t.p_date, t.n_date, t.p_topic, t.n_topic, t.p_link, t.n_link, t.fluke, v_bhmin), p_date = t.p_date, n_date = t.n_date from ripples.att_hop_tests t where t.hop_id = f.hop_id and t.look_no = f.look_no and f.hop_id = r.hop_id;
    end if;
  end loop;

  -- one weighted BH over the actual family (frozen weights, renormalised so Σw = m over the hops in this run; Genovese–Roeder–Wasserman);
  -- real + decoy + controls in the same run
  create temp table _bh on commit drop as
  select hop_id, look_no, p_bh, w, p_bh / w pw, row_number() over (order by p_bh / w, hop_id) rk
  from (select f.*, coalesce(f.bh_weight, 1) * m / sum(coalesce(f.bh_weight, 1)) over () w from _fin f) x;
  create temp table _q on commit drop as
  select hop_id, look_no, least(1, min(m * pw / rk) over (order by rk desc rows between unbounded preceding and current row)) q_w, w from _bh;
  if p_reexam then
    -- B5: a re-examined hop is re-scored inside its OWN frozen BH family (the finalised looks of the day it was resolved on) with only
    -- its own p replaced; every other member keeps the p and weight it had. Nothing about the original rows changes.
    delete from _q;
    for r in select f.hop_id, f.look_no, f.p_bh, f.bh_weight from _fin f loop
      select t.look_day, c.reconstructed into v_orig from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
       where t.hop_id = r.hop_id and t.look_no < 100 and t.q_w is not null order by t.look_no desc limit 1;
      select array_agg(x.hop_id order by x.hop_id), array_agg(x.p order by x.hop_id), array_agg(x.w order by x.hop_id) into fam_ids, fam_p, fam_w
        from (select t.hop_id, coalesce((t.detail -> 'bh' ->> 'p_bh')::float8, t.fluke::float8) p, coalesce(c.bh_weight, 1)::float8 w
                from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
               where t.look_day = v_orig.look_day and t.look_no < 100 and t.q_w is not null and c.reconstructed = v_orig.reconstructed
                 and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = t.hop_id and t2.look_no < 100 and t2.q_w is not null)) x;
      fam_i := array_position(fam_ids, r.hop_id);
      if fam_i is null then fam_ids := array[r.hop_id]; fam_p := array[r.p_bh::float8]; fam_w := array[coalesce(r.bh_weight, 1)::float8]; fam_i := 1;
      else fam_p[fam_i] := r.p_bh; end if;
      select array_agg(w * cardinality(fam_w) / s.tot order by o) into fam_w from unnest(fam_w) with ordinality u(w, o), (select sum(w) tot from unnest(fam_w) w) s;
      fam_q := ripples.att_bh_q(fam_p, fam_w);
      insert into _q values (r.hop_id, r.look_no, fam_q[fam_i], fam_w[fam_i]);
    end loop;
    m := (select count(*) from _fin);
  end if;
  update ripples.att_hop_tests t set q_w = q.q_w, q = q.q_w, detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('bh', jsonb_build_object('m', m, 'weight', round(q.w::numeric, 4), 'p_bh', f.p_bh))
    from _q q join _fin f on f.hop_id = q.hop_id and f.look_no = q.look_no where q.hop_id = t.hop_id and q.look_no = t.look_no;

  -- fluke bins need today's q_w; H-tercile from the day's family
  update ripples.att_hop_tests t set h_score = ripples.att_hiddenness(t.hop_id) from _fin f where f.hop_id = t.hop_id and f.look_no = t.look_no;
  with hb as (select t.hop_id, t.look_no, ntile(3) over (order by t.h_score) hb from ripples.att_hop_tests t join _fin f on f.hop_id = t.hop_id and f.look_no = t.look_no)
  update ripples.att_hop_tests t set h_bin = hb.hb from hb where hb.hop_id = t.hop_id and hb.look_no = t.look_no;
  fj := ripples.att_fluke_bins_refresh(p_as_of);
  warming := (fj ->> 'warming')::boolean;

  -- tiers
  for r in select f.*, t.q_w, t.s_by_channel, t.attention_only, t.common_shock, t.attribution, t.loso_ok, t.lag_ok, t.link_kind, t.detail,
                  t.n_families, t.h_bin, t.flags, t.rho_raw, t.provisional
           from _fin f join ripples.att_hop_tests t on t.hop_id = f.hop_id and t.look_no = f.look_no order by f.hop_id loop
    n_tested := n_tested + 1; sum_p := sum_p + coalesce(r.p_h, 1);
    select family into fam from ripples.att_events where event_id = r.event_id;
    select tier, coalesce(provisional, false) into prev_tier, prev_prov from ripples.att_hop_tests t where t.hop_id = r.hop_id and t.look_no < r.look_no and t.tier is not null order by look_no desc limit 1;
    select published_tier, frozen_att into pub_tier, frozen from ripples.att_hop_registry where hop_id = r.hop_id;
    -- post-publication freezing of READ/SRCH/SOC evidence: attention ž fixed at the published look (upgrades need outcome evidence)
    sbc := coalesce(r.s_by_channel, '{}'::jsonb);
    if pub_tier in ('likely','measured') and frozen is not null then
      sbc := sbc || frozen;
      update ripples.att_hop_tests t set s_by_channel = sbc where t.hop_id = r.hop_id and t.look_no = r.look_no;
    end if;
    select coalesce(array_agg(k), '{}') into v_agree from jsonb_each(sbc) e(k, v) where (v ->> 'zhat')::float8 >= 3;
    -- final look for the longest window among the agreeing channels
    longest_final := null;
    select l_by_channel into v_lbc from ripples.att_hop_candidates where hop_id = r.hop_id;
    foreach ch in array v_agree loop
      -- S5: the frozen per-channel L (pre-6.1 hops: the channel prior in effect at their freeze)
      longest_final := greatest(coalesce(longest_final, '1900-01-01'::date), (select max(d) from unnest(ripples.att_look_dates(ch, (select onset from ripples.att_hop_candidates where hop_id = r.hop_id), ripples.att_hop_l_frozen(v_lbc, ch))) d));
    end loop;
    v_final_agree := longest_final is not null and r.look_day >= longest_final;
    v_kappa_min := coalesce((r.detail ->> 'kappa_min')::float8, (select min((v ->> 'kappa')::float8) from jsonb_each(sbc) e(k, v)), 0);
    v_broken := exists (select 1 from ripples.att_breaker b where b.tripped_at is not null and b.restored_at is null
                        and b.cell = r.path_type || '×' || coalesce((select k from jsonb_each(sbc) e(k, v) where (v ->> 'zhat')::float8 >= 3
                                                                    order by (select cs2.kind from ripples.att_channel_stat cs2 where cs2.channel = k) = 'outcome' desc limit 1), 'none'));
    v_parent_tier := case when r.parent_hop is null then 'root' else coalesce((select tier from ripples.att_hop_tests t where t.hop_id = r.parent_hop and t.tier is not null order by look_no desc limit 1), 'none') end;
    -- substantive Measured failures first (they become the card's named reason); the q / final-look condition is appended last
    fails := '{}';
    if coalesce((r.detail ->> 'n_out3')::int, 0) < 1 then fails := array_append(fails, 'attention ripple'); end if;
    if not (cardinality(v_agree) >= 2 or (coalesce((r.detail ->> 'n_out3')::int, 0) >= 1 and r.link_kind in ('mechanism','measured','comention'))) then fails := array_append(fails, 'one channel only'); end if;
    if r.link_kind = 'structural' and cardinality(v_agree) < 2 then fails := array_append(fails, 'linkage is structural only'); end if;
    if not coalesce(r.lag_ok, true) then fails := array_append(fails, 'lag order'); end if;
    if coalesce(r.common_shock, false) then fails := array_append(fails, 'common shock day'); end if;
    if coalesce(r.s_pre, 0) >= 2 then fails := array_append(fails, 'already moving'); end if;
    if coalesce((r.attribution ->> 'share')::float8, 1) < 0.5 then fails := array_append(fails, 'also consistent with ' || coalesce((select string_agg(x ->> 'label', ', ') from jsonb_array_elements(r.attribution -> 'rivals') x), 'a rival')); end if;
    if not coalesce(r.loso_ok, true) then fails := array_append(fails, 'one source carries it'); end if;
    if v_kappa_min < 0.5 then fails := array_append(fails, 'source still warming up'); end if;
    if v_parent_tier not in ('root','measured') then fails := array_append(fails, 'if the previous step holds'); end if;
    if v_broken then fails := array_append(fails, 'circuit breaker'); end if;
    if warming and coalesce(r.p_h, 1) > 0.02 then fails := array_append(fails, 'fluke rate warming up'); end if;
    if coalesce(r.n_families, 0) < 2 then fails := array_append(fails, 'placebo families'); end if;
    if r.flags @> array['young_series'] then fails := array_append(fails, 'series younger than two years'); end if;   -- B3
    -- rarity gate across families: p_h = max_f p_f must be ≤ 0.05 for Measured (≤ 0.20 for Likely), which is what the spec's p_h-based
    -- BH implied; BH itself runs on the date family, the only one with the 2,000-draw resolution
    if coalesce(r.p_h, 1) > q_meas then fails := array_append(fails, 'a placebo family disagrees'); end if;
    if not (r.q_w <= q_meas) then fails := array_append(fails, 'q above 0.05');
    elsif not (v_final_agree or r.is_final) then fails := array_append(fails, 'final look not reached'); end if;
    cs := coalesce(r.common_shock, false);
    gate_lik := coalesce(r.p_h, 1) <= q_lik;
    -- tier assignment with hysteresis (promote at q ≤ 0.05, demote at q > 0.10). Interim looks grant at most Likely (provisional) at
    -- q_w ≤ 0.01 (ENGINE §5.2, §7); plain Likely at q_w ≤ 0.20 needs the final look (of the hop, or of the longest agreeing channel).
    v_prov := false;
    v_at_final := r.is_final or v_final_agree;
    if cardinality(fails) = 0 then
      v_tier := 'measured'; v_reason := null;
    elsif prev_tier = 'measured' and r.q_w <= q_dem and (select count(*) from unnest(fails) x where x not in ('final look not reached', 'q above 0.05')) = 0 then
      v_tier := 'measured'; v_reason := null;
    elsif v_at_final and r.q_w <= q_lik and gate_lik then
      v_tier := 'likely'; v_reason := fails[1];
      if r.attention_only then v_reason := 'attention ripple'; end if;
    elsif not v_at_final and r.q_w <= q_prov and gate_lik then
      v_tier := 'likely'; v_prov := true; v_reason := coalesce(case when r.attention_only then 'attention ripple' end, fails[1], 'provisional');
    elsif prev_tier in ('likely','measured') and r.q_w <= q_dem and gate_lik then
      v_tier := 'likely'; v_reason := coalesce(fails[1], 'holding'); v_prov := not v_at_final;
    elsif r.look_day >= r.window_close + 1 or r.is_final then
      v_tier := 'flat'; v_reason := 'window closed, no move';
    else
      v_tier := 'watching'; v_reason := null;
    end if;
    if v_tier = 'likely' and v_reason is null then v_reason := 'probably linked; a fluke is not ruled out'; end if;
    -- reversed / common_cause chains never reach Likely
    if (r.flags @> array['reversed']) and v_tier in ('likely','measured') then v_tier := case when r.is_final then 'flat' else 'watching' end; v_reason := 'reversed'; end if;
    -- retraction: a published Likely/Measured hop that drops below Likely, or a published Measured now on a common-shock day
    if pub_tier in ('likely','measured') and (v_tier in ('flat','watching') or (pub_tier = 'measured' and cs)) then
      v_tier := 'retracted';
      v_reason := case when cs then 'common shock flag now covers the onset' when coalesce((r.attribution ->> 'share')::float8, 1) < 0.5 then 'a later event explains it better'
                       when coalesce(prev_prov, false) and not (r.flags @> array['reexam']) then 'provisional signal did not hold at the final look'   -- S10
                       when r.flags @> array['reexam'] then 'revised data or recalibration pushed q above 0.10 at re-examination'
                       else 'revised data or recalibration pushed q above 0.10' end;
      n_retract := n_retract + 1;
    end if;
    -- fluke rate f from the decoy-calibrated bins
    fb := ripples.att_fluke_lookup(p_as_of, r.t_stat, coalesce(r.h_bin, 0));
    -- shrunk multiple on the best agreeing outcome channel (else best agreeing channel)
    rho := null; v_ch := null; best := null;
    select k, v into v_ch, best from jsonb_each(sbc) e(k, v) where (v ->> 'zhat')::float8 >= 3
      order by (select cs2.kind from ripples.att_channel_stat cs2 where cs2.channel = k) = 'outcome' desc, (v ->> 'zhat')::float8 desc limit 1;
    if best is not null then
      select sigma, value_kind into z from ripples.att_zvec where series_id = (best ->> 'best_series')::bigint;
      if z.sigma is not null then
        rho := ripples.att_shrunk_rho(v_ch, case when best ->> 'stat' = 'car' then (best ->> 'S')::float8 / sqrt(greatest((best ->> 'l')::float8, 1)) else (best ->> 'S')::float8 end
                                      * case when (select sign from ripples.att_hop_candidates where hop_id = r.hop_id) = -1 then -1 else 1 end,
                                      (best ->> 'sd')::float8, z.sigma, z.value_kind);
      end if;
    end if;
    update ripples.att_hop_tests t set tier = v_tier, tier_reason = v_reason, provisional = v_prov,
           f = (fb ->> 'f')::real, f_bin = fb ->> 'bin',
           rho_shrunk = (rho ->> 'rho')::real, rho_lo = (rho ->> 'lo')::real, rho_hi = (rho ->> 'hi')::real, rho_raw = coalesce((rho ->> 'raw')::real, t.rho_raw),
           retracted_at = case when v_tier = 'retracted' then now() else t.retracted_at end,
           retract_reason = case when v_tier = 'retracted' then v_reason else t.retract_reason end,
           detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('fails', to_jsonb(fails), 'final_agree', v_final_agree, 'prev_tier', prev_tier, 'rho', rho)
     where t.hop_id = r.hop_id and t.look_no = r.look_no;
    if v_tier = 'measured' then n_meas := n_meas + 1; sum_f := sum_f + coalesce((fb ->> 'f')::float8, 0); end if;
    if v_tier in ('measured','likely') then n_moved := n_moved + 1; end if;
    if v_tier = 'flat' then n_flat := n_flat + 1; end if;
    if v_tier = 'watching' then n_watch := n_watch + 1; end if;
    if v_tier = 'retracted' then
      v_seq := ripples.att_ledger_append(p_as_of, 'retract', jsonb_build_object('hop_id', r.hop_id, 'look', r.look_no),
                                         jsonb_build_object('hop_id', r.hop_id, 'reason', v_reason, 'day', p_as_of, 'q', r.q_w));
      update ripples.att_hop_tests t set ledger_seq = v_seq where t.hop_id = r.hop_id and t.look_no = r.look_no;
    end if;
    -- B5: a demotion or retraction propagates to the hop's children ("if the previous step holds")
    -- keyed on what the reader last saw: the published tier when the hop is published, else the previous look's tier
    if coalesce(pub_tier, prev_tier) in ('likely','measured') and v_tier not in ('likely','measured') or (coalesce(pub_tier, prev_tier) = 'measured' and v_tier = 'likely') then
      n_retract := n_retract + ripples.att_propagate_parent(r.hop_id, v_tier, p_as_of);
    end if;
    -- registry resolution at the final look
    if r.is_final then
      update ripples.att_hop_registry g set resolved_at = coalesce(g.resolved_at, now()), hit = v_tier in ('likely','measured'), final_tier = v_tier where g.hop_id = r.hop_id;
      update ripples.att_hop_candidates set status = 'tested' where hop_id = r.hop_id;
    end if;
  end loop;

  -- day line + ledger resolve row (hash of the day's tier assignments)
  select jsonb_agg(jsonb_build_array(t.hop_id, t.look_no, t.tier, round(t.q_w::numeric, 6), round(coalesce(t.f, -1)::numeric, 4)) order by t.hop_id) into tiers
    from ripples.att_hop_tests t join _fin f on f.hop_id = t.hop_id and f.look_no = t.look_no;
  v_seq := ripples.att_ledger_append(p_as_of, 'resolve', jsonb_build_object('as_of', p_as_of, 'm', m, 'library', p_library, 'reexam', p_reexam),
             jsonb_build_object('as_of', p_as_of, 'tiers', tiers, 'line', jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_flukes', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3))));
  -- the day line: live runs own 'engine.day.<as_of>' (the site's day line); library / reconstructed runs write 'engine.libday.<as_of>'
  perform ripples.att_state_set(case when p_reexam then 'engine.reexam.' when p_library then 'engine.libday.' else 'engine.day.' end || p_as_of, jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_flukes', round(sum_f::numeric, 3),
                                'sum_p', round(sum_p::numeric, 3), 'flat', n_flat, 'watching', n_watch, 'retracted', n_retract, 'ledger_seq', v_seq, 'warming', warming));
  -- event status and cascade payloads for every event touched today
  for e in select distinct event_id from _fin union select distinct event_id from _nf loop
    perform ripples.att_event_status(e.event_id, p_as_of);
    perform ripples.att_build_cascade(e.event_id, p_as_of);
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'flat', n_flat, 'watching', n_watch,
                            'retracted', n_retract, 'expected_flukes', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3), 'warming', warming, 'ledger_seq', v_seq);
end $$;

-- S10: att_build_cascade labels
create or replace function ripples.att_build_cascade(p_event bigint, p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev record; nodes jsonb := '[]'::jsonb; flat jsonb := '[]'::jsonb; r record; n_tested int; n_moved int; n_meas int; sum_f float8; sum_p float8;
        weakest text; depth int; payload jsonb; ctrl jsonb; ideas jsonb; rivals jsonb; spark jsonb; emoji text; ver int; v_hash text; txt text;
        best jsonb; v_ch text; dom text; node jsonb; due date; label text; p1 int; f1 int; crossed int; route text; ss jsonb; st text; hops_txt text;
        u_series bigint; sentence text;
begin
  select * into ev from ripples.att_events where event_id = p_event;
  if not found then return null; end if;
  select coalesce(a.emoji, '◌') into emoji from ripples.articles a where a.qid = ev.qid;
  -- hops with their latest finalised look
  emoji := coalesce(emoji, '◌');
  for r in
    select c.hop_id, c.depth, c.parent_hop, c.node, c.path, c.path_type, c.window_close, c.looks, c.channels, c.sign, c.prior,
           t.look_no, t.tier, t.tier_reason, t.provisional, t.attention_only, t.rho_shrunk, t.rho_lo, t.rho_hi, t.lag_days, t.t_v, t.fluke, t.f, t.f_bin,
           t.q_w, t.s_by_channel, t.retracted_at, t.retract_reason, t.t_stat, t.detail, t.h_score, t.flags, t.is_final, t.link_kind, t.replication
    from ripples.att_hop_candidates c
    left join lateral (select * from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier is not null order by t.look_no desc limit 1) t on true
    where c.event_id = p_event and c.frozen_hash is not null and c.role <> 'negative_control'
    order by c.depth, c.hop_id
  loop
    v_ch := null; best := null;
    select k, v into v_ch, best from jsonb_each(coalesce(r.s_by_channel, '{}'::jsonb)) e(k, v) where (v ->> 'zhat')::float8 >= 3
      order by (select kind from ripples.att_channel_stat where channel = k) = 'outcome' desc, (v ->> 'zhat')::float8 desc limit 1;
    if v_ch is null then select k, v into v_ch, best from jsonb_each(coalesce(r.s_by_channel, '{}'::jsonb)) e(k, v) order by (v ->> 'zhat')::float8 desc nulls last limit 1; end if;
    dom := case when r.node ~ '^Q[0-9]+$' then ripples.att_domain_of(coalesce(v_ch, 'READ')) else ripples.att_domain_of(coalesce((select ns.channel from ripples.att_node_series ns where ns.node = r.node limit 1), 'READ')) end;
    label := ripples.att_node_label(r.node);
    if r.tier is null or r.tier = 'watching' then
      select min(d) into due from unnest(r.looks) d where d > p_as_of;
      node := jsonb_build_object('hop_id', r.hop_id, 'depth', r.depth, 'parent_hop', r.parent_hop, 'node', r.node, 'label', label, 'domain', dom,
                'kind', case when exists (select 1 from ripples.att_node_series ns join ripples.att_channel_stat cs on cs.channel = ns.channel where ns.node = r.node and cs.kind = 'outcome') then 'outcome' else 'attention' end,
                'tier', 'watching', 'tier_reason', r.tier_reason, 'provisional', false, 'attention_ripple', false, 'window_close', r.window_close, 'due', due,
                'path', r.path, 'p_hat', (select p_hat from ripples.att_hop_registry where hop_id = r.hop_id), 'retracted', null, 'fork_of', null);
      nodes := nodes || node;
      continue;
    end if;
    if r.tier = 'flat' then
      flat := flat || jsonb_build_object('hop_id', r.hop_id, 'node', r.node, 'label', label, 'domain', dom, 'parent_hop', r.parent_hop, 'reason', coalesce(r.tier_reason, 'window closed, no move'),
                                         'rho', r.rho_shrunk, 'path_type', r.path_type);
      continue;
    end if;
    p1 := case when r.fluke > 0 then floor(1 / r.fluke)::int end;
    f1 := case when r.f is null then null when r.f <= 0 then 50 else least(50, floor(1 / r.f)::int) end;   -- S10: f = 0 (no decoy passed in the bin) prints '50+', not 'warming up'
    crossed := (select count(distinct ripples.att_domain_of(k)) from jsonb_each(r.s_by_channel) e(k, v) where (v ->> 'zhat')::float8 >= 3);
    route := coalesce(r.replication ->> 'route', 'na');
    ss := case when best is not null and (best ->> 'best_series') is not null then ripples.att_spark((best ->> 'best_series')::bigint, p_as_of, 60) end;
    sentence := case r.tier
      when 'measured' then format('%s ran %s× its normal, starting %s day(s) after %s. A random pairing looks this strong about 1 in %s times. Links like this turn out to be flukes about 1 in %s times. Consistent with a ripple from %s. Measured movement, not proof of cause.',
                                  label, round(coalesce(r.rho_shrunk, 1)::numeric, 2), coalesce(r.lag_days::text, '?'), ev.label, coalesce(p1::text, '?'),
                                  case when f1 is null then 'warming up' when f1 >= 50 then '50+' else f1::text end, ev.label)
      when 'retracted' then format('Retracted %s: %s.', to_char(r.retracted_at, 'YYYY-MM-DD'), r.retract_reason)
      else case when r.attention_only then 'Readers moved together; nothing outside attention has moved yet.' else 'Probably linked; a fluke isn''t ruled out. ' || coalesce(r.tier_reason, '') end end
      || case when r.depth >= 2 then ' … if the previous step holds.' else '' end;
    node := jsonb_build_object('hop_id', r.hop_id, 'depth', r.depth, 'parent_hop', r.parent_hop, 'node', r.node, 'label', label, 'domain', dom,
              'kind', case when exists (select 1 from ripples.att_node_series ns join ripples.att_channel_stat cs on cs.channel = ns.channel where ns.node = r.node and cs.kind = 'outcome') then 'outcome' else 'attention' end,
              'tier', r.tier, 'tier_reason', r.tier_reason, 'provisional', coalesce(r.provisional, false),
              'attention_ripple', coalesce(r.attention_only, false),
              'rho', r.rho_shrunk, 'rho_lo', r.rho_lo, 'rho_hi', r.rho_hi, 'lag_days', r.lag_days, 'onset', r.t_v,
              'p', r.fluke, 'p_1_in', p1, 'f', r.f, 'f_1_in', f1, 'f_warming', r.f is null, 'q', r.q_w,
              'channels', jsonb_build_object('agree', (select count(*) from jsonb_each(r.s_by_channel) e(k, v) where (v ->> 'zhat')::float8 >= 3), 'of', (select count(*) from jsonb_object_keys(r.s_by_channel))),
              'crossed_domains', crossed, 'window_close', r.window_close, 'due', (select min(d) from unnest(r.looks) d where d > p_as_of),
              'route', route, 'fork_of', r.detail -> 'fork_of', 'retracted', case when r.tier = 'retracted' then jsonb_build_object('date', to_char(r.retracted_at, 'YYYY-MM-DD'), 'reason', r.retract_reason) end,
              'spark', ss -> 'spark', 'band', ss -> 'band', 'unit', ss ->> 'unit', 'path', r.path, 'linkage', r.link_kind, 'sentence', sentence,
              'hidden', r.h_score, 'flags', to_jsonb(r.flags),
              'chain', r.detail -> 'chain', 'lag_from_event_days', (r.detail ->> 'lag_from_event_days')::int);   -- 6.1.2: chaining record + event lag for the story layer
    nodes := nodes || node;
  end loop;
  -- denominators (every frozen candidate counts, incl. waiting_series and flat)
  select count(*) into n_tested from ripples.att_hop_candidates c where c.event_id = p_event and c.frozen_hash is not null and c.role <> 'negative_control';
  select count(*) filter (where n ->> 'tier' in ('measured','likely')), count(*) filter (where n ->> 'tier' = 'measured'),
         coalesce(sum((n ->> 'f')::float8) filter (where n ->> 'tier' in ('measured','likely')), 0)
    into n_moved, n_meas, sum_f from jsonb_array_elements(nodes) n;
  select coalesce(sum(t.fluke), 0) into sum_p from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
    where c.event_id = p_event and c.role <> 'negative_control' and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = t.hop_id and t2.fluke is not null);
  weakest := case when exists (select 1 from jsonb_array_elements(nodes) n where n ->> 'tier' = 'likely') then 'likely'
                  when n_meas > 0 then 'measured' when jsonb_array_length(nodes) > 0 then 'watching' else null end;
  select coalesce(max((n ->> 'depth')::int), 0) into depth from jsonb_array_elements(nodes) n where n ->> 'tier' in ('measured','likely');
  -- control ripple: the decoys matched to this event, their stops
  select jsonb_build_object('event_id', min(d.event_id), 'label', 'a page that wasn''t trending',
           'stops', jsonb_build_object('measured', coalesce(sum(s.measured), 0), 'likely', coalesce(sum(s.likely), 0), 'watching', coalesce(sum(s.watching), 0), 'flat', coalesce(sum(s.flat), 0)))
    into ctrl
    from ripples.att_events d
    left join lateral (
      select count(*) filter (where t.tier = 'measured') measured, count(*) filter (where t.tier = 'likely') likely,
             count(*) filter (where coalesce(t.tier, 'watching') = 'watching') watching, count(*) filter (where t.tier = 'flat') flat
      from ripples.att_hop_candidates c
      left join lateral (select tier from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier is not null order by look_no desc limit 1) t on true
      where c.event_id = d.event_id and c.frozen_hash is not null) s on true
    where d.role = 'decoy' and d.matched_to = p_event;
  -- route ideas (IO edges from the event's node; never tested)
  select coalesce(jsonb_agg(jsonb_build_object('text', ripples.att_node_label(m.from_node) || ' → ' || ripples.att_node_label(m.to_node) || ' (input-output link)',
                                               'source', 'BEA 2017 IO table', 'status', 'hypothesis, not measured')), '[]'::jsonb)
    into ideas from (select * from ripples.att_mech_edges m where m.etype = 'IO' and m.valid_to is null and m.from_node in (ev.qid, 'family:' || ev.family) limit 5) m;
  select coalesce(jsonb_agg(distinct jsonb_build_object('event_id', x.event_id, 'label', x.label, 'note', 'also active this week')), '[]'::jsonb) into rivals
    from (select distinct (rv ->> 'event_id')::bigint event_id, rv ->> 'label' label
          from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id, jsonb_array_elements(coalesce(t.attribution -> 'rivals', '[]'::jsonb)) rv
          where c.event_id = p_event) x;
  select s.series_id into u_series from ripples.att_series s where s.topic_id = ev.topic_id and s.source = 'wiki.pv' order by (s.geo = 'en.wikipedia') desc limit 1;
  spark := case when u_series is not null then ripples.att_spark(u_series, p_as_of, 90) end;
  st := ripples.att_event_status(p_event, p_as_of);
  select coalesce(version, 0) into ver from ripples.att_cascades where event_id = p_event;
  ver := coalesce(ver, 0);
  select string_agg(case (n ->> 'domain') when 'real_world' then '🛫' when 'institutions' then '🏛' when 'jobs' then '💼' when 'builders' then '🧰' when 'markets' then '🎯' when 'economy' then '📈' when 'consumption' then '🎮' else '📖' end, '━')
    into hops_txt from jsonb_array_elements(nodes) n where n ->> 'tier' in ('measured','likely') and (n ->> 'depth')::int = 1;
  txt := format('%s %s ━%s · %s stop%s in %s days, %s · consistent with, not proof of cause · https://bensunter.com/ripples/line/%s/v%s/',
                emoji, ev.label, coalesce(hops_txt, '…'), n_moved, case when n_moved = 1 then '' else 's' end, greatest(0, p_as_of - ev.onset),
                case st when 'running' then 'still running' when 'ended' then 'line ended' else 'went nowhere' end, coalesce(ev.slug, ev.event_id::text), ver + 1);
  payload := jsonb_build_object('v', 2,
    'event', jsonb_build_object('event_id', ev.event_id, 'slug', ev.slug, 'label', ev.label, 'emoji', emoji, 'family', ev.family, 'sensitive', ev.sensitive,
                                'reconstructed', ev.reconstructed, 'onset', ev.onset, 'magnitude_x', case when ev.magnitude is not null then round(exp(ev.magnitude)::numeric, 1) end,
                                'spark', spark -> 'spark', 'baseline', jsonb_build_object('from', ev.onset - 111, 'to', ev.onset - 21), 'why', '[]'::jsonb),
    'version', ver, 'as_of', p_as_of, 'status', st, 'method', coalesce(ripples._att_cfg('engine') ->> 'method', '6.0'),
    'denominators', jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_false_links', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3),
                                       'warming', coalesce((select warming from ripples.att_fluke_bins b where b.as_of = (select max(as_of) from ripples.att_fluke_bins) limit 1), true),
                                       'expected_false_links_label', case when coalesce((select warming from ripples.att_fluke_bins b where b.as_of = (select max(as_of) from ripples.att_fluke_bins) limit 1), true) then 'warming up' else round(sum_f::numeric, 3)::text end),
    'weakest_tier', weakest, 'depth', depth, 'nodes', nodes, 'flat', flat, 'route_ideas', ideas, 'control', ctrl, 'rivals', rivals,
    'text_share', txt, 'ledger', jsonb_build_object('head', ripples.att_ledger_head()));
  v_hash := encode(extensions.digest(ripples._canon(payload - 'as_of' - 'ledger' - 'version')::text, 'sha256'), 'hex');
  payload := payload || jsonb_build_object('payload_hash', v_hash);
  insert into ripples.att_cascades(event_id, version, payload, denominators, weakest_tier, sum_f, updated_at, payload_hash)
  values (p_event, ver, payload, payload -> 'denominators', weakest, sum_f, now(), v_hash)
  on conflict (event_id) do update set payload = excluded.payload, denominators = excluded.denominators, weakest_tier = excluded.weakest_tier,
    sum_f = excluded.sum_f, updated_at = now(), payload_hash = excluded.payload_hash;
  return payload;
end $$;

-- B2: att_heldout_p (null keyed on the pair onset)
create or replace function ripples.att_heldout_p(p_series bigint, p_onset date, p_end date, p_draws int default 200) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare bundle jsonb; b record; res jsonb; t_h float8; d date; tv float8; exceed int := 0; n int := 0; lo date; hi date;
        dd date[] := '{}'; k int; gate boolean;
begin
  perform ripples.att_hb_reset();
  perform ripples.att_hb_load(array[p_series]);
  select * into b from _hb where series_id = p_series;
  if not found then return jsonb_build_object('p', null, 'reason', 'no zvec'); end if;
  bundle := jsonb_build_array(jsonb_build_object('series_id', p_series, 'channel', b.channel));
  res := ripples.att_hop_stat_b(bundle, p_onset, p_end, 0, '{}', null, false, true, p_onset);
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
    res := ripples.att_hop_stat_b(bundle, dd[k], dd[k] + (p_end - p_onset), 0, '{}', null, false, true, p_onset);
    tv := (res ->> 'T')::float8;
    continue when tv is null;
    continue when gate and coalesce((res ->> 's_pre')::float8, 0) >= 2;   -- gated-out draw: neither a draw nor an exceedance (same rule as att_run_placebos)
    n := n + 1;
    if tv >= t_h then exceed := exceed + 1; end if;
  end loop;
  -- calibration p is the fixed-n estimate (1+exceed)/(1+n): no Besag–Clifford stop here, so the held-out p keeps the 1/(n+1) resolution
  -- a uniformity (KS) check needs; the hop tests' sequential p is the same quantity truncated early
  if n < 30 then return jsonb_build_object('p', null, 'reason', 'few draws', 'n', n); end if;
  return jsonb_build_object('p', (1 + exceed)::float8 / (1 + n), 'n', n, 't', t_h, 'exceed', exceed);
end $$;

-- B2: att_spikein (pre-onset robust null; the published power curve)
create or replace function ripples.att_spikein(p_as_of date, p_per_channel int default 25) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v_delta float8; lagv int; v_hl float8; ar real[]; i int; t0 date; i0 int; v_kind text; l int; sdj jsonb; s jsonb; zs float8;
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
    -- a clean past onset (deterministic), ≥ 140 d after the array start and ≥ 60 d before its end; the null scale is the pre-onset robust scale (B2)
    i0 := 140 + (abs(hashtext(r.series_id::text || p_as_of::text)) % greatest(1, r.n - 200));
    t0 := r.from_day + (i0 - 1);
    sdj := ripples.att_sd_null_calc(r.ar, r.from_day, r.n, l, v_kind, 1, t0, r.channel = 'PHYS');
    continue when (sdj ->> 'sd') is null;
    sd := (sdj ->> 'sd')::real; mu := coalesce((sdj ->> 'mean')::real, 0);
    foreach v_delta in array array[1, 2, 3, 5] loop
      foreach lagv in array array[0, 1, 3, 7] loop
        foreach v_hl in array array[1, 3, 7] loop
          ar := r.ar;
          for i in i0 + lagv .. least(r.n, i0 + lagv + 30) loop
            if ar[i] is not null then ar[i] := ar[i] + v_delta * exp(-ln(2) * (i - i0 - lagv) / v_hl); end if;
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
          insert into _sp(channel, delta, lag, hl, tested, hits) values (r.channel, v_delta, lagv, v_hl, 1, hit::int)
          on conflict (channel, delta, lag, hl) do update set tested = _sp.tested + 1, hits = _sp.hits + excluded.hits;
        end loop;
      end loop;
    end loop;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'delta', delta, 'lag', lag, 'half_life', hl, 'tested', tested, 'recall', round((hits::numeric / nullif(tested, 0)), 3)) order by channel, delta, lag, hl), '[]'::jsonb)
    into out from _sp;
  return out;
end $$;

-- B1: att_run_positive_control (slug lookup, fixture meta)
create or replace function ripples.att_run_positive_control(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k record; ev bigint; res jsonb; ok boolean := false; nodes jsonb; got jsonb; x text; missing text[] := '{}'; likely jsonb := '[]'::jsonb;
begin
  select * into k from ripples.att_controls where id = p_id and kind = 'positive';
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such control'); end if;
  -- B1: the control event is looked up by its slug (the geo-annotated WS-A control event with meta.ba / meta.state); created with the
  -- fixture's meta when no such event exists. The bare-label lookup used to create twins without geo meta.
  if k.spec ? 'slug' then select event_id into ev from ripples.att_events where slug = k.spec ->> 'slug' and role = 'positive_control'; end if;
  if ev is null then ev := ripples.att_library_event(k.spec ->> 'qid', k.spec ->> 'label', k.spec ->> 'family', (k.spec ->> 'onset')::date, 'positive_control', k.spec -> 'meta'); end if;
  if k.spec ? 'meta' then update ripples.att_topics t set meta = coalesce(t.meta, '{}'::jsonb) || (k.spec -> 'meta') where t.topic_id = (select topic_id from ripples.att_events where event_id = ev); end if;
  res := ripples.att_run_library(ev);
  select coalesce(jsonb_agg(jsonb_build_object('node', h.node, 'tier', h.tier, 'q', h.q_w, 'T', h.t_stat, 'reason', h.tier_reason, 'fails', h.detail -> 'fails')), '[]'::jsonb)
    into nodes from ripples.att_hop_latest h where h.event_id = ev;
  got := '[]'::jsonb;
  for x in select jsonb_array_elements_text(k.spec -> 'expect') loop
    if exists (select 1 from ripples.att_hop_latest h where h.event_id = ev and h.node = x and h.tier = 'measured') then got := got || to_jsonb(x); else missing := array_append(missing, x); end if;
  end loop;
  ok := case when coalesce((k.spec ->> 'any_of')::boolean, false) then jsonb_array_length(got) > 0 else cardinality(missing) = 0 end;
  for x in select jsonb_array_elements_text(coalesce(k.spec -> 'also_likely', '[]'::jsonb)) loop
    if exists (select 1 from ripples.att_hop_latest h where h.event_id = ev and h.node = x and h.tier in ('likely','measured')) then likely := likely || to_jsonb(x); end if;
  end loop;
  update ripples.att_controls set last_run = current_date, passed = ok,
         detail = jsonb_build_object('event_id', ev, 'measured', got, 'missing', to_jsonb(missing), 'also_likely', likely, 'nodes', nodes, 'run', res) where id = p_id;
  return jsonb_build_object('id', p_id, 'name', k.spec ->> 'name', 'ok', ok, 'measured', got, 'missing', to_jsonb(missing), 'event_id', ev);
end $$;

-- S10: att_calibrate (realised p floors, method notes)
create or replace function ripples.att_calibrate(p_as_of date default current_date - 1) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ks jsonb; power jsonb; arsc jsonb; fdr jsonb; brk jsonb; rep jsonb; pri jsonb; rc jsonb; payload jsonb; v_seq bigint; t0 timestamptz := clock_timestamp();
        receipts jsonb; refire jsonb; retr jsonb; ctrl jsonb; ks_bad boolean; mv jsonb; head text;
begin
  ks := ripples.att_calibrate_ks(p_as_of, 500);
  ks_bad := (ks ->> 'p') is not null and (ks ->> 'p')::float8 < 0.01;
  power := ripples.att_spikein(p_as_of, 25);
  -- empirical daily AR scale per channel (1.4826·MAD and sd over the last 2 years, median across a deterministic 1-in-3 sample of series):
  -- the spike-in's "+δσ" is in nominal z units; this says what one unit is worth on real series
  select coalesce(jsonb_agg(jsonb_build_object('channel', ch, 'series', n, 'mad', round(mad::numeric, 2), 'sd', round(sd::numeric, 2)) order by ch), '[]'::jsonb) into arsc
  from (select ch, count(*) n, percentile_cont(0.5) within group (order by mad) mad, percentile_cont(0.5) within group (order by sd) sd
        from (select ripples.att_series_channel(z.series_id) ch, z.series_id,
                     1.4826 * percentile_cont(0.5) within group (order by abs(u.v)) mad, stddev_samp(u.v) sd
              from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id, unnest(z.ar[greatest(1, z.n - 729):z.n]) u(v)
              where z.grain = 'day' and z.kappa >= 0.5 and s.key <> '__total__' and z.series_id % 3 = 0 and u.v is not null
              group by z.series_id) x group by ch) y;
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
                                         from ripples.att_hop_latest where role = 'negative_control' and not reconstructed and look_day >= p_as_of - 90 and freeze_proven))
    into ctrl from ripples.att_controls;
  select coalesce(jsonb_agg(jsonb_build_object('seq', seq, 'day', day, 'hash', payload_hash, 'ref', ref) order by seq), '[]'::jsonb) into mv from ripples.att_ledger where kind = 'model_version';
  head := ripples.att_ledger_head();
  payload := jsonb_build_object('v', 2, 'as_of', p_as_of, 'method', coalesce(ripples._att_cfg('engine') ->> 'method', '6.0'),
    'decoy_fdr', fdr - 'as_of' - 'days', 'null_ks', ks, 'power', power, 'ar_scale', arsc, 'controls', ctrl, 'receipts', receipts, 'refire', refire,
    'breaker', brk -> 'open', 'retractions', retr, 'ledger', jsonb_build_object('head', head, 'seq', (select max(seq) from ripples.att_ledger)),
    'model_versions', mv, 'priors', pri, 'fluke_bins', (select coalesce(jsonb_agg(jsonb_build_object('s_bin', s_bin, 'h_bin', h_bin, 'f', f, 'decoy_tested', decoy_tested, 'real_tested', real_tested, 'warming', warming) order by s_bin, h_bin), '[]'::jsonb)
                                                          from ripples.att_fluke_bins where as_of = (select max(as_of) from ripples.att_fluke_bins)),
    'p_floors', jsonb_build_object('date', 1.0 / 2001, 'date_default', 1.0 / 201, 'topic', 1.0 / 301, 'link', 1.0 / 201,
                                   'note', 'nominal; the realised floors below are what the trailing 90 days of final looks actually had',
                                   'realised', (select jsonb_build_object('n_final_looks', count(*),
                                       'date', jsonb_build_object('median_n', percentile_cont(0.5) within group (order by n_date), 'median_floor', percentile_cont(0.5) within group (order by 1.0 / (1 + n_date))),
                                       'topic', jsonb_build_object('median_n', percentile_cont(0.5) within group (order by n_topic), 'median_floor', percentile_cont(0.5) within group (order by 1.0 / (1 + n_topic)), 'share_with_30', avg((coalesce(n_topic, 0) >= 30)::int)),
                                       'link', jsonb_build_object('median_n', percentile_cont(0.5) within group (order by n_link), 'share_with_30', avg((coalesce(n_link, 0) >= 30)::int)),
                                       'p_floor_median', percentile_cont(0.5) within group (order by p_floor))
                                     from ripples.att_hop_latest h where h.is_final and h.look_day >= p_as_of - 90 and h.t_stat is not null)),
    'bh_input', 'p_h = max over the placebo families with ≥ 30 draws (engine 6.1); the date family alone was the BH input before 2026-09-26',
    'null_scale', '1.4826·MAD of the window statistic over pre-onset windows (ending ≥ L + 30 d before the onset, trailing 3 y; PHYS skips 2020-03..2021-06); floors 0.5 (peak) / 1.0 (CAR); series with < 20 % distinct windows are excluded',
    'day_lines', (select coalesce(jsonb_agg(jsonb_build_object('day', substr(k, 12), 'line', v) order by k), '[]'::jsonb) from ripples.att_state where k like 'engine.day.%' and k >= 'engine.day.' || (p_as_of - 30)::text));
  v_seq := ripples.att_ledger_append(p_as_of, 'calibration', jsonb_build_object('as_of', p_as_of), payload);
  payload := payload || jsonb_build_object('ledger', jsonb_build_object('head', ripples.att_ledger_head(), 'seq', v_seq));
  insert into ripples.att_calibration_public(as_of, payload) values (p_as_of, payload) on conflict (as_of) do update set payload = excluded.payload;
  return jsonb_build_object('as_of', p_as_of, 'ks', ks - 'hist', 'fdr', fdr -> 'overall', 'breaker', brk, 'replication', rep, 'priors', pri, 'corr', rc,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1), 'ledger_seq', v_seq);
end $$;


-- ---------------------------------------------------------------------------------------------------------------------
-- B5. Nightly re-examination of settled hops (ENGINE §7 retraction triggers 1–3 for hops whose looks are all closed)
-- ---------------------------------------------------------------------------------------------------------------------
-- For every hop published (or resolved) as Likely/Measured, the frozen final look is recomputed on today's arrays (same window, same
-- data end, same L, current att_zvec / common days / rivals / null scale) and stored as a NEW look row (look_no ≥ 100, flag 'reexam').
-- att_finalize(p_as_of, p_library, true) then re-scores those rows inside each hop's own frozen BH family, runs the ordinary tier and
-- retraction logic (so a published hop that no longer holds is retracted with a ledger row) and propagates to the children.
-- Once per hop per day; at most p_budget_s seconds of tests per call (the rest waits for the next night).
create or replace function ripples.att_reexamine(p_as_of date default current_date, p_library boolean default false, p_budget_s int default 900) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h record; n int := 0; n_skip int := 0; t0 timestamptz := clock_timestamp(); n_re int; fin jsonb; r jsonb;
begin
  for h in
    select g.hop_id, cardinality(c.looks) n_looks
    from ripples.att_hop_registry g join ripples.att_hop_candidates c on c.hop_id = g.hop_id
    where c.frozen_hash is not null and c.reconstructed = p_library and c.status <> 'skipped'
      and (g.published_tier in ('likely','measured') or g.final_tier in ('likely','measured'))
      and exists (select 1 from ripples.att_hop_tests t where t.hop_id = g.hop_id and t.look_no < 100 and t.is_final and t.t_stat is not null and t.q_w is not null)
      and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = g.hop_id and t.look_no >= 100 and (t.detail ->> 'reexam_day')::date = p_as_of)
      and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = g.hop_id and t.tier = 'retracted')
    order by (g.published_tier = 'measured') desc, g.hop_id
  loop
    if clock_timestamp() - t0 > make_interval(secs => p_budget_s) then n_skip := n_skip + 1; continue; end if;
    select count(*) into n_re from ripples.att_hop_tests t where t.hop_id = h.hop_id and t.look_no >= 100;
    r := ripples.att_engine_job(jsonb_build_object('hop_id', h.hop_id, 'look', h.n_looks, 'store_look', 100 + n_re + 1, 'reexam_day', p_as_of));
    n := n + 1;
  end loop;
  fin := case when n > 0 then ripples.att_finalize(p_as_of, p_library, true) end;
  perform ripples.att_state_set('engine.reexam', jsonb_build_object('day', p_as_of, 'library', p_library, 'reexamined', n, 'deferred', n_skip,
                                'finalize', fin, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1), 'at', now()));
  return jsonb_build_object('as_of', p_as_of, 'reexamined', n, 'deferred', n_skip, 'finalize', fin, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;


-- ---------------------------------------------------------------------------------------------------------------------
-- S14. Recompute stepper that commits in chunks. The previous version ran every pending reconstructed look of a group inside one
-- transaction (7,000+ looks after a reset) and never finished inside pg_cron's statement timeout. This one (a) waits for the nightly
-- zvec build, (b) runs pending live looks / finalizes per live day, (c) runs pending reconstructed looks earliest-look-day-first within
-- the call's budget (each call commits), and (d) only when nothing is pending, finalizes / chains / rebuilds cascades one group per
-- iteration. Same functions, same order per hop, only the transaction boundaries differ.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_recompute_step(p_budget_s int default 600) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb := ripples.att_state_get('engine.recompute'); t0 timestamptz := clock_timestamp(); ev bigint; d date; last_look date;
        n_ran int := 0; r jsonb; i int; n_groups int; ld date; zv jsonb := ripples.att_state_get('zvec.run'); done int := 0; pend date; all_ev bigint[];
begin
  if st is null or st ? 'finished' then return jsonb_build_object('idle', true); end if;
  if zv is null or not (zv ? 'finished') or (zv ->> 'day')::date < (st ->> 'started')::date - 1 then
    return jsonb_build_object('waiting', 'zvec rebuild', 'zvec', zv - 'sources' - 'pending' - 'done');
  end if;
  if not coalesce((st ->> 'live_done')::boolean, false) then
    for ld in select x::date from jsonb_array_elements_text(st -> 'live_days') x order by 1 loop
      r := ripples.att_engine_run_due(ld, 100000, false, p_budget_s); n_ran := n_ran + (r ->> 'ran')::int;
      if (r ->> 'left_over')::int > 0 then
        st := st || jsonb_build_object('looks_ran', coalesce((st ->> 'looks_ran')::int, 0) + n_ran);
        perform ripples.att_state_set('engine.recompute', st);
        return jsonb_build_object('live_ran', n_ran, 'live_day', ld, 'left_over', r -> 'left_over');
      end if;
      perform ripples.att_finalize(ld, false); perform ripples.att_chain_decide(ld);
    end loop;
    st := st || jsonb_build_object('live_done', true, 'live_ran', coalesce((st ->> 'live_ran')::int, 0) + n_ran, 'looks_ran', coalesce((st ->> 'looks_ran')::int, 0) + n_ran);
    perform ripples.att_state_set('engine.recompute', st);
    return jsonb_build_object('live_ran', n_ran, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
  end if;
  -- (c) pending reconstructed looks of the recompute's own groups (event + decoys + negatives), earliest look day first, within the budget
  select array_agg(e.event_id) into all_ev from ripples.att_events e
   where e.event_id in (select (g ->> 'event_id')::bigint from jsonb_array_elements(st -> 'groups') g)
      or e.matched_to in (select (g ->> 'event_id')::bigint from jsonb_array_elements(st -> 'groups') g);
  loop
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
    select min(u.d) into pend
      from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
     where c.frozen_hash is not null and c.status <> 'skipped' and c.reconstructed and c.event_id = any(all_ev) and u.d <= current_date
       and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'));
    exit when pend is null;
    r := ripples.att_engine_run_group(all_ev, pend, greatest(10, p_budget_s - extract(epoch from clock_timestamp() - t0)::int));
    n_ran := n_ran + (r ->> 'ran')::int;
    st := st || jsonb_build_object('looks_ran', coalesce((st ->> 'looks_ran')::int, 0) + (r ->> 'ran')::int, 'pending_day', pend, 'last_chunk', r);
    perform ripples.att_state_set('engine.recompute', st);
    exit when (r ->> 'left_over')::int > 0 or (r ->> 'ran')::int = 0;
  end loop;
  if pend is not null then
    return jsonb_build_object('looks_ran', n_ran, 'pending_day', pend, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
  end if;
  -- (d) nothing pending: finalize per group
  n_groups := jsonb_array_length(st -> 'groups'); i := (st ->> 'next')::int;
  while i < n_groups and clock_timestamp() - t0 < make_interval(secs => p_budget_s) loop
    ev := (st -> 'groups' -> i ->> 'event_id')::bigint;
    select max(l) into last_look from ripples.att_hop_candidates c join ripples.att_events e on e.event_id = c.event_id, unnest(c.looks) l
     where c.frozen_hash is not null and c.reconstructed and (e.event_id = ev or e.matched_to = ev) and l <= current_date;
    if last_look is not null then
      perform ripples.att_finalize(last_look, true, false, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = ev or e.matched_to = ev));   -- BH family = the event group
      perform ripples.att_chain_decide(last_look);
    end if;
    perform ripples.att_build_cascade(ev, coalesce(last_look, current_date));
    i := i + 1; done := done + 1;
    st := st || jsonb_build_object('next', i, 'last', jsonb_build_object('event_id', ev, 'last_look', last_look, 'at', now()));
    perform ripples.att_state_set('engine.recompute', st);
  end loop;
  if i >= n_groups then
    st := st || jsonb_build_object('finished', now());
    perform ripples.att_state_set('engine.recompute', st);
  end if;
  return jsonb_build_object('groups_done', done, 'next', i, 'of', n_groups, 'finished', st ? 'finished', 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- 6.1: the chunked recompute must never run while a zvec rebuild is rewriting arrays (looks would mix array states),
-- and a single cron statement stays under the launcher's freeze budget (≤ 100 s).
create or replace function ripples.att_recompute_step_locked(p_budget_s integer default 600)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare r jsonb; v_s7 jsonb; v_run jsonb;
begin
  select v into v_s7 from ripples.att_state where k = 'zvec.s7';
  select v into v_run from ripples.att_state where k = 'zvec.run';
  if v_s7 is not null and not (v_s7 ? 'finished') then return jsonb_build_object('skipped', 'zvec S7 rebuild in progress'); end if;
  if v_run is not null and not (v_run ? 'finished') then return jsonb_build_object('skipped', 'zvec rebuild in progress'); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_recompute_step')) then return jsonb_build_object('skipped', 'another stepper holds the lock'); end if;
  begin
    r := ripples.att_recompute_step(least(coalesce(p_budget_s, 50), 100));
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_recompute_step'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_recompute_step'));
  return r;
end $function$;
revoke all on function ripples.att_recompute_step_locked(integer) from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------------------------------
-- B1. Positive-control fixtures: slug of the geo-annotated control event, its meta (ba / state), regional expectations.
--   * Helene / Milton: the national tsa.pax dip is not in the data (audit E1: ž ≈ 0.2 / 0.4); the expectation is regional — grid demand
--     in the affected balancing authorities (storm_grid_demand, sign −1), the state FEMA declaration, NWS warnings (template L = 7).
--   * ChatGPT: hn.algolia is an attention channel and is capped at Likely by ENGINE §1.6, so it can never satisfy "Measured"; it is kept
--     as an also_likely expectation. The Measured expectation is npm.dl:openai.
--   * Llama 3 / DeepSeek-R1: WS-E's npm expectation stands (pypi / hf keep no history before 2025-08).
-- Fixture targets only; no threshold, weight or statistic is changed. Recorded as a model_version ledger row.
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare v_seq bigint; changes jsonb;
begin
  update ripples.att_controls k set spec = k.spec || jsonb_build_object(
      'slug', 'lib-control-hurricane-helene-2024',
      'meta', jsonb_build_object('ba', jsonb_build_array('CPLE','DUK','FPC','FPL','SC','SCEG','SOCO','TVA'), 'state', jsonb_build_array('FL','GA','NC','SC','TN','VA')),
      'expect', jsonb_build_array('eia.930:FPC','eia.930:FPL','eia.930:DUK','eia.930:CPLE','eia.930:SCEG','fema.decl:st:FL','fema.decl:st:NC','fema.decl:st:GA','iem.warn:__total__'),
      'expect_was_6_0', coalesce(k.spec -> 'expect_was', k.spec -> 'expect'),
      'expect_note', 'regional (audit B1): the national tsa.pax dip is not supported by the data; affected-BA grid demand, state declarations and NWS warnings are')
   where kind = 'positive' and spec ->> 'name' = 'Helene → TSA / FEMA / IEM';
  update ripples.att_controls k set spec = k.spec || jsonb_build_object(
      'slug', 'lib-control-hurricane-milton-2024',
      'meta', jsonb_build_object('ba', jsonb_build_array('FPC','FPL'), 'state', jsonb_build_array('FL')),
      'expect', jsonb_build_array('eia.930:FPL','eia.930:FPC','fema.decl:st:FL','iem.warn:__total__'),
      'expect_was_6_0', coalesce(k.spec -> 'expect_was', k.spec -> 'expect'),
      'expect_note', 'regional (audit B1): the national tsa.pax dip is not supported by the data; Florida grid demand, the FL declaration and NWS warnings are')
   where kind = 'positive' and spec ->> 'name' = 'Milton → TSA / FEMA / IEM';
  update ripples.att_controls k set spec = k.spec || jsonb_build_object(
      'expect', jsonb_build_array('npm.dl:openai'), 'also_likely', jsonb_build_array('hn.algolia:chatgpt'),
      'expect_was_6_0', coalesce(k.spec -> 'expect_was', k.spec -> 'expect'),
      'expect_note', 'hn.algolia is an attention channel (capped at Likely, ENGINE §1.6): it is expected Likely+, not Measured')
   where kind = 'positive' and spec ->> 'name' = 'ChatGPT launch → npm openai / HN';
  update ripples.att_controls k set spec = k.spec || jsonb_build_object(
      'slug', 'lib-control-texas-heat-dome-2023',
      'meta', jsonb_build_object('ba', jsonb_build_array('ERCO','SWPP'), 'state', jsonb_build_array('TX')))
   where kind = 'positive' and spec ->> 'name' = 'Texas heat dome → ERCOT demand';
  update ripples.att_controls k set spec = k.spec || jsonb_build_object('slug', 'lib-control-llama-3-2024')
   where kind = 'positive' and spec ->> 'name' = 'Llama 3 release → HF / npm / pypi';
  update ripples.att_controls k set spec = k.spec || jsonb_build_object('slug', 'lib-control-deepseek-r1-2025')
   where kind = 'positive' and spec ->> 'name' = 'DeepSeek-R1 release → HF / pypi';
  select jsonb_agg(jsonb_build_object('id', id, 'name', spec ->> 'name', 'slug', spec ->> 'slug', 'expect', spec -> 'expect', 'also_likely', spec -> 'also_likely') order by id)
    into changes from ripples.att_controls where kind = 'positive';
  v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('controls_fixture', 'engine-6.1'),
             jsonb_build_object('controls_fixture', 'engine-6.1', 'fixtures', changes,
                                'note', 'fixture targets only (slug lookup of the geo-annotated control events, regional storm expectations, HN as also_likely); no threshold, weight or statistic changed'));
end $$;

-- the method bump itself: a model_version ledger row (hash of config, seed priors, templates, channel table and mappers)
select ripples.att_model_version_register();


-- ---------------------------------------------------------------------------------------------------------------------
-- Cron (UTC): att-reexamine 08:55 daily (after finalize 08:20, before the archive driver resumes); holidays registered now.
-- att-wse-looks (WS-E ops stepper) is unscheduled: it ran reconstructed looks without waiting for the nightly zvec build; the chunked
-- att_recompute_step above does the same work in date order and waits for the build. att-recompute is (re)scheduled every minute.
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare j record; begin
  for j in select jobid from cron.job where jobname in ('att-reexamine', 'att-wse-looks', 'att-recompute') loop perform cron.unschedule(j.jobid); end loop;
end $$;
select cron.schedule('att-reexamine', '55 8 * * *', $$set statement_timeout = '25min'; select ripples.att_reexamine(current_date, false, 900)$$);
select cron.schedule('att-recompute', '* * * * *', $$set statement_timeout = '110s'; select ripples.att_recompute_step_locked(50)$$);   -- short: pg_cron launches nothing while a long job statement runs on this instance

select ripples.att_common_days_refresh(current_date - 1);

do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'ripples' and c.relkind = 'r' and c.relname like 'att\_%' loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on table ripples.%I from anon, authenticated, public', t);
  end loop;
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;

-- (the deploy-gate stepper lives in 17_chunked_gate.sql: att_controls_step(p_budget_s), one ≤ 50 s chunk per minute)
revoke all on function ripples.att_controls_step() from anon, authenticated, public;
-- select cron.schedule('att-controls-loop', '* * * * *', $$set statement_timeout = '110s'; select ripples.att_controls_step(50) where (select v ? 'finished' from ripples.att_state where k = 'zvec.run')$$);


-- ---------------------------------------------------------------------------------------------------------------------
-- S7 rebuild stepper: re-run att_zvec_series for the same-weekday sources in ≤ p_budget_s chunks (aggregate keys first, so the regional
-- demeaning finds the rebuilt aggregate), then att_zvec_demean per source. State in att_state 'zvec.s7'. Never inside the 05:40–08:50 window.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_zvec_rebuild_step(p_sources text[] default null, p_budget_s int default 45, p_day date default current_date - 1) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb := coalesce(ripples.att_state_get('zvec.s7'), '{}'::jsonb); t0 timestamptz := clock_timestamp(); sid bigint; n int := 0; src text; v_phi float8; v_nobs int;
begin
  if (now() at time zone 'utc')::time between '05:40' and '08:50' then return jsonb_build_object('skipped', 'nightly window'); end if;
  if st ? 'finished' and p_sources is null then return st - 'pending'; end if;
  if not (st ? 'pending') or p_sources is not null then
    st := jsonb_build_object('started', now(), 'day', p_day, 'sources', to_jsonb(coalesce(p_sources, (select array_agg(source) from ripples.att_engine_source_map where same_dow))),
            'pending', (select coalesce(jsonb_agg(s.series_id order by (s.key = coalesce(m.agg_key, '')) desc, s.source, s.series_id), '[]'::jsonb)
                        from ripples.att_series s join ripples.att_engine_source_map m on m.source = s.source
                        where s.source = any(coalesce(p_sources, (select array_agg(source) from ripples.att_engine_source_map where same_dow))) and s.last_day >= p_day - 60),
            'done', 0);
    perform ripples.att_state_set('zvec.s7', st);
  end if;
  while jsonb_array_length(st -> 'pending') > 0 and clock_timestamp() - t0 < make_interval(secs => p_budget_s) loop
    sid := (st -> 'pending' ->> 0)::bigint;
    select s.source, coalesce((ripples.att_state_get('zvec.phi.' || s.source) ->> 'phi')::float8, 0), coalesce(z.n_obs, 0) into src, v_phi, v_nobs
      from ripples.att_series s left join ripples.att_zvec z on z.series_id = s.series_id where s.series_id = sid;
    perform ripples.att_zvec_series(sid, (st ->> 'day')::date, case when v_nobs >= 400 then v_phi * v_nobs / (v_nobs + 50.0) else 0 end);
    st := st || jsonb_build_object('pending', (st -> 'pending') - 0, 'done', (st ->> 'done')::int + 1);
    n := n + 1;
  end loop;
  if jsonb_array_length(st -> 'pending') = 0 then
    for src in select x from jsonb_array_elements_text(st -> 'sources') x loop perform ripples.att_zvec_demean(src, (st ->> 'day')::date); end loop;
    perform ripples.att_common_days_refresh((st ->> 'day')::date);
    st := st || jsonb_build_object('finished', now());
  end if;
  perform ripples.att_state_set('zvec.s7', st);
  return (st - 'pending') || jsonb_build_object('this_call', n, 'left', jsonb_array_length(st -> 'pending'));
end $$;
revoke all on function ripples.att_zvec_rebuild_step(text[], int, date) from anon, authenticated, public;
-- select cron.schedule('att-zvec-s7', '* * * * *', $$set statement_timeout = '110s'; select ripples.att_zvec_rebuild_step(null, 45)$$);  -- unschedule once 'zvec.s7' carries 'finished'

-- ---------------------------------------------------------------------------------------------------------------------
-- Staged harness (engine 6.1.1). The single-statement att_test_engine() takes 25–30 min and pg_cron launches nothing while it
-- runs. att_test_step(budget) runs the same T1–T17 as a state machine in att_state 'engine.test.stage', each call ≤ budget s
-- (cron: every minute, statement_timeout 110 s), so collectors and other agents' jobs keep running. The synthetic fixture
-- therefore persists between calls (no rollback): the cleanup stage removes every fixture row and marks the fixture's freeze
-- ledger rows superseded_by = 'fixture-cleanup' (the ledger is append-only; att_ledger_verify and T5 skip superseded batches).
-- Start:  select ripples.att_test_stage_start(null);            -- or array['T5','T7','T9','T13','T17']
--         select cron.schedule('att-test-step', '* * * * *', $$set statement_timeout = '110s'; select ripples.att_test_step(50)$$);
-- Result: att_state 'engine.test' (ok, tests[], staged = true); the step unschedules its own cron job when finished.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_test_stage_start(p_only text[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb;
begin
  st := jsonb_build_object('stage', 'pure', 'only', to_jsonb(p_only), 'started', now(), 'res', '[]'::jsonb, 't0', current_date - 45, 'nser', 80,
                           'need_fixture', p_only is null or exists (select 1 from unnest(p_only) x where x in ('T7','T8','T9','T10','T11','T12','T17','T50','T51','T52')),
                           'calls', 0, 'seconds', 0);
  perform ripples.att_state_set('engine.test.stage', st);
  perform ripples.att_state_set('engine.test.request', jsonb_build_object('status', 'staged', 'only', to_jsonb(p_only), 'at', now()));
  return st - 'res';
end $$;
revoke all on function ripples.att_test_stage_start(text[]) from anon, authenticated, public;

create or replace function ripples._att_want(p_st jsonb, p_test text) returns boolean
language sql immutable set search_path = '' as $$
  select p_st -> 'only' is null or jsonb_typeof(p_st -> 'only') = 'null' or p_st -> 'only' ? p_test
$$;

create or replace function ripples.att_test_step(p_budget_s int default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb := ripples.att_state_get('engine.test.stage'); res jsonb; ok boolean; j jsonb; j2 jsonb; j3 jsonb; arr real[]; s jsonb; s2 jsonb; q float8[];
        t0 date; i int; nser int; v_sid bigint; v_ev bigint; grp bigint[]; a date; fr jsonb; r record; n int := 0; last_look date; fin jsonb;
        v_hop bigint; v_look smallint; aa jsonb; bb jsonb; lv jsonb; ledger_ok boolean; tamper jsonb; bad_keys jsonb; h record; v_recomp text;
        n_inj_meas int; n_null_likely int; n_decoy_meas int; n_decoy_tested int; ps float8[]; ks jsonb; v_child bigint; v_q_before real;
        tt timestamptz := clock_timestamp(); stage text; ctx text; ids bigint[]; hashes text[]; pre_common boolean; v_verify jsonb;
begin
  if st is null or st ? 'finished' or st ->> 'stage' in ('finished', 'failed') then return jsonb_build_object('idle', true); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_test_step')) then return jsonb_build_object('skipped', 'running'); end if;
  stage := st ->> 'stage'; res := coalesce(st -> 'res', '[]'::jsonb); t0 := (st ->> 't0')::date; nser := coalesce((st ->> 'nser')::int, 80);
  v_ev := (st ->> 'event_id')::bigint;
  if st ? 'group' then select array_agg(x::bigint) into grp from jsonb_array_elements_text(st -> 'group') x; end if;
  begin
  -- ------------------------------------------------------------------------------------------------------------ pure tests
  if stage = 'pure' then
    if ripples._att_want(st, 'T1') then
      ok := abs(ripples.att_norm_inv(0.975) - 1.959964) < 1e-4 and abs(ripples.att_norm_cdf(1.96) - 0.9750021) < 1e-5 and abs(ripples.att_norm_cdf(ripples.att_norm_inv(0.001)) - 0.001) < 1e-6;
      res := ripples._att_t(res, 'T1 normal cdf/quantile', ok, null);
      ok := abs(ripples.att_nb_midp_z(5, 5, null)) < 0.25 and ripples.att_nb_midp_z(15, 5, null) > 3 and ripples.att_nb_midp_z(15, 5, 2) < ripples.att_nb_midp_z(15, 5, null) and ripples.att_nb_midp_z(5000, 3, null) > 6;
      res := ripples._att_t(res, 'T1 NB mid-p z (Poisson centre, tail, overdispersion, underflow)', ok, null);
      ok := ripples.att_holiday('2025-11-27') = 'us_thanksgiving' and ripples.att_holiday('2025-12-25') = 'us_xmas' and ripples.att_holiday('2025-12-27') = 'xmas_week' and ripples.att_holiday('2026-04-03') = 'uk_goodfriday'
            and ripples.att_holiday('2026-07-03') = 'us_july4' and ripples.att_holiday('2026-09-25') = '' and ripples.att_easter(2026) = '2026-04-05';
      res := ripples._att_t(res, 'T1 holidays', ok, null);
    end if;
    if ripples._att_want(st, 'T2') then
      select array_agg((case when g = 300 then 5.0 when g = 301 then 4.0 else 0.0 end)::real order by g) into arr from generate_series(1, 420) g;
      s := ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', 1, 0, '2026-12-31', false);
      s2 := ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'car', 1, 0.5, '2026-12-31', false);
      ok := (s ->> 'S')::float8 = 5 and (s ->> 'lag')::int = 2 and abs((s2 ->> 'S')::float8 - 9.0 / (sqrt(8) * sqrt(3))) < 1e-9
            and (ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', -1, 0, '2026-12-31', false) ->> 'S')::float8 = 0
            and (ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', 0, 0, '2026-12-31', false) ->> 'S')::float8 = 5;
      res := ripples._att_t(res, 'T2 window statistic: peak, signed/unsigned, CAR = Σ/(√n·√((1+ρ)/(1−ρ)))', ok, jsonb_build_object('peak', s, 'car', s2));
      ok := abs(ripples.att_rho1(arr, '2025-01-01', 420, '2025-01-01'::date + 297)) < 1e-9;
      res := ripples._att_t(res, 'T2 rho1 of a flat baseline is 0', ok, null);
    end if;
    if ripples._att_want(st, 'T3') then
      perform setseed(0.42);
      select array_agg(((random() * 2 - 1) * 1.7)::real order by g) into arr from generate_series(1, 420) g;
      s := ripples.att_sd_null_calc(arr, '2025-01-01', 420, 7, 'car', 1); s2 := ripples.att_sd_null_calc(arr, '2025-01-01', 420, 7, 'peak', 1);
      ok := abs((s ->> 'sd')::float8 - 0.98) < 0.15 and (s2 ->> 'mean')::float8 between 1.2 and 1.8 and (s ->> 'n')::int >= 250;
      res := ripples._att_t(res, 'T3 sd_null: CAR ≈ 1 on iid noise, peak null mean ≈ 1.5 (centred ž needed)', ok, jsonb_build_object('car', s, 'peak', s2));
    end if;
    if ripples._att_want(st, 'T4') then
      q := ripples.att_bh_q(array[0.001, 0.01, 0.02, 0.5], array[1, 1, 1, 1]);
      ok := abs(q[1] - 0.004) < 1e-9 and abs(q[2] - 0.02) < 1e-9 and abs(q[3] - 0.0266667) < 1e-6 and abs(q[4] - 0.5) < 1e-9;
      q := ripples.att_bh_q(array[0.02, 0.01], array[5, 0.2]);
      ok := ok and q[1] < q[2] and abs(q[1] - 2 * 0.02 / 5 / 1) < 1e-9;
      res := ripples._att_t(res, 'T4 weighted BH step-up (pure)', ok, null);
    end if;
    if ripples._att_want(st, 'T13') then
      perform setseed(0.42);
      select array_agg(((random() * 2 - 1) * 0.6)::real order by g) into arr from generate_series(1, 1200) g;
      j := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1);
      select array_agg((case when g in (300, 700, 1100) then 12.0 else 0.0 end)::real order by g) into arr from generate_series(1, 1200) g;
      j2 := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 2, 'peak', 1);
      perform setseed(0.11);
      select array_agg((case when g <= 600 then (random() * 2 - 1) * 1.7 else (random() * 2 - 1) * 40 end)::real order by g) into arr from generate_series(1, 1200) g;
      j3 := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1, '2022-01-01'::date + 560, false);
      s := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1);
      ok := (j ->> 'sd')::float8 = 1.0 and (j ->> 'floored')::boolean and (j2 ->> 'sd') is null and j2 ->> 'reason' = 'degenerate'
            and (j3 ->> 'sd')::float8 < 1.5 and (s ->> 'sd')::float8 > 2.5 * (j3 ->> 'sd')::float8 and (j3 ->> 'to')::date <= '2022-01-01'::date + 560 - 7 - 30 - 7;
      res := ripples._att_t(res, 'T13 null scale: robust MAD with floors, degenerate series excluded, pre-onset windows only', ok, jsonb_build_object('iid', j, 'dormant', j2, 'pre_onset', j3 - 'from', 'whole_array', s - 'from' - 'to'));
    end if;
    if ripples._att_want(st, 'T14') then
      ok := (select count(*) from ripples.att_common_days where day in ('2025-11-26', '2025-11-27', '2025-11-28', '2025-12-26', '2026-07-03', '2024-11-28')) = 6
            and not exists (select 1 from ripples.att_common_days where day = '2025-11-19');
      res := ripples._att_t(res, 'T14 US federal holidays ± 1 d, Black Friday and Christmas week are registered common-shock days', ok, null);
    end if;
    if ripples._att_want(st, 'T15') then
      insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
      values (null, 'test:geo:ny', 'test NY event', 'en', 'panel', false, 'cascade', '{"state": ["NY", "NJ"], "family": "hazard.storm"}'::jsonb),
             (null, 'test:geo:fl', 'test FL event', 'en', 'panel', false, 'cascade', '{"state": ["FL"], "family": "hazard.storm"}'::jsonb),
             (null, 'test:geo:none', 'test no-geo event', 'en', 'panel', false, 'cascade', '{"family": "hazard.storm"}'::jsonb)
      on conflict (label_key) do nothing;
      ok := (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:ny'))) = 1
            and (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:fl'))) = 0
            and (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:none'))) = 0
            and (select count(*) from ripples.att_resolve_targets('{"node":"tsa.pax:checkpoint","sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:fl'))) = 1;
      res := ripples._att_t(res, 'T15 geo_filter honoured in target resolution (state ∩ filter; no state meta → not proposed)', ok, null);
      delete from ripples.att_topics where label_key like 'test:geo:%';
    end if;
    if ripples._att_want(st, 'T16') then
      ok := ripples.att_look_dates('INST', '2025-11-26', 7) = array['2025-12-04'::date] and ripples.att_look_dates('INST', '2025-11-26', 90) = array['2025-12-27'::date, '2026-01-26', '2026-02-25']
            and ripples.att_hop_l('INST', 'storm_nws_warnings') = 7 and ripples.att_hop_l('INST', 'storm_fema_decl') = 90 and ripples.att_hop_l('PHYS', null) = 7;
      res := ripples._att_t(res, 'T16 template L honoured per channel at freeze (INST 7 → one look at +8; INST 90 → +31/+61/+91)', ok, null);
    end if;
    if ripples._att_want(st, 'T5') then
      v_verify := ripples.att_ledger_verify();
      ok := (v_verify ->> 'ok')::boolean;
      for h in select l.seq, l.payload_hash fh, (l.ref ->> 'as_of')::date as_of, (l.ref ? 'refreeze_of') refrozen from ripples.att_ledger l
               where l.kind = 'freeze' and not (l.ref ? 'superseded_by') and l.ref ? 'as_of' and not (l.ref ? 'object') loop
        v_recomp := ripples.att_freeze_hash(h.as_of, false, h.fh);
        ok := ok and v_recomp = h.fh
              and (h.refrozen or abs((select sum(bh_weight) - count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)) < 1e-2 * greatest(1, (select count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)));
      end loop;
      res := ripples._att_t(res, 'T5 every frozen batch recomputes bit-identically and its BH weights sum to m', ok,
               jsonb_build_object('ledger_verify', v_verify - 'bad', 'bad', v_verify -> 'bad',
                                  'other_freeze_objects', (select coalesce(jsonb_agg(jsonb_build_object('seq', seq, 'object', ref ->> 'object', 'method', ref ->> 'method')), '[]'::jsonb) from ripples.att_ledger where kind = 'freeze' and ref ? 'object')));
      ok := not exists (select 1 from ripples.att_hop_tests t where not exists (select 1 from ripples.att_hop_candidates c where c.hop_id = t.hop_id and c.frozen_hash is not null));
      res := ripples._att_t(res, 'T5 no att_hop_tests row without a frozen candidate', ok, null);
    end if;
    if ripples._att_want(st, 'T6') then
      ok := not exists (select 1 from ripples.att_hop_candidates c join ripples.att_node_series ns on ns.node = c.node where ns.channel = 'MONEY')
            and not exists (select 1 from ripples.att_hop_candidates c, jsonb_array_elements(c.path) p where p ->> 'type' = 'IO')
            and not exists (select 1 from ripples.att_hop_tests where tier = 'measured' and attention_only);
      res := ripples._att_t(res, 'T6 MONEY zero tests, IO zero tests, attention-only never Measured', ok, null);
    end if;
    stage := case when (st ->> 'need_fixture')::boolean then 'fixture' else 'cleanup' end;
  -- ------------------------------------------------------------------------------------------------------------ fixture rows
  elsif stage = 'fixture' then
    -- 70 null series + 10 with an injected +0.3 log-unit response for 7 days after t0; 1,200 days of iid log-noise, no weekly pattern
    insert into ripples.att_sources(source, family, channel, grade, value_kind, grain, history_from, quality, enabled, reason, needs_secret, policy_d1, tier,
                                    attribution, license_note, per_run_cap, per_day_cap, spacing_ms, budget_bucket, hosts, robots_required, backfill_fn)
    values ('test.synth', 'test', 'physical', 'green', 'level', 'day', current_date - 1200, 1, true, 'engine test fixture', null, false, 'test', 'synthetic', 'none', null, null, 0, null, '{}', false, null)
    on conflict (source) do nothing;
    insert into ripples.att_engine_source_map(source, channel, value_kind, same_dow, agg_key, domain) values ('test.synth', 'PHYS', 'level', false, null, 'real_world') on conflict (source) do update set same_dow = excluded.same_dow;
    insert into ripples.att_families(family, label, scheduled, mapper) values ('test.synth', 'Synthetic test family', false,
      (select jsonb_agg(jsonb_build_object('node', 'test.synth:s' || lpad(g::text, 2, '0'), 'sign', 1, 'template', 'test_injected'))
         from (select g from generate_series(1, 10) g union all select g from generate_series(71, 80) g) x))
    on conflict (family) do update set mapper = excluded.mapper;
    perform setseed(0.7);
    for i in 1..nser loop
      insert into ripples.att_series(source, metric, geo, key, last_day) values ('test.synth', 'n', 'US', 's' || lpad(i::text, 2, '0'), current_date - 1)
      on conflict (source, metric, geo, key) do update set last_day = excluded.last_day returning series_id into v_sid;
      delete from ripples.attention_obs where series_id = v_sid;
      insert into ripples.attention_obs(series_id, day, value)
      select v_sid, d::date, exp(5 + 0.05 * (random() * 2 - 1) * 1.7 + case when i > 70 and d::date between t0 and t0 + 6 then 0.30 else 0 end)
      from generate_series(current_date - 1200, current_date - 1, interval '1 day') d;
    end loop;
    -- T50/T51 (6.1.2): s81 = 0.6 × s71 two days later + own noise (a mediated child: its shock arrives through s71); s82 = its own copy of the
    -- shock at t0 with independent noise (a fork: the event moves it directly, no residual s71 → s82 association)
    for i in 81..82 loop
      insert into ripples.att_series(source, metric, geo, key, last_day) values ('test.synth', 'n', 'US', 's' || i, current_date - 1)
      on conflict (source, metric, geo, key) do update set last_day = excluded.last_day returning series_id into v_sid;
      delete from ripples.attention_obs where series_id = v_sid;
      if i = 81 then
        insert into ripples.attention_obs(series_id, day, value)
        select v_sid, o.day + 2, exp(5 + 0.05 * (random() * 2 - 1) * 1.7 + 0.6 * (ln(o.value) - 5))
        from ripples.attention_obs o join ripples.att_series s71 on s71.series_id = o.series_id
        where s71.source = 'test.synth' and s71.key = 's71' and o.day + 2 <= current_date - 1;
      else
        insert into ripples.attention_obs(series_id, day, value)
        select v_sid, d::date, exp(5 + 0.05 * (random() * 2 - 1) * 1.7 + case when d::date between t0 and t0 + 6 then 0.30 else 0 end)
        from generate_series(current_date - 1200, current_date - 1, interval '1 day') d;
      end if;
    end loop;
    delete from ripples.att_zvec where series_id in (select series_id from ripples.att_series where source = 'test.synth');
    stage := 'zvec';
  -- ------------------------------------------------------------------------------------------------------------ arrays, chunked
  elsif stage = 'zvec' then
    for r in select s.series_id from ripples.att_series s where s.source = 'test.synth' and not exists (select 1 from ripples.att_zvec z where z.series_id = s.series_id) order by s.series_id loop
      exit when clock_timestamp() - tt > make_interval(secs => p_budget_s);
      perform ripples.att_zvec_series(r.series_id, current_date - 1, 0);
      n := n + 1;
    end loop;
    if not exists (select 1 from ripples.att_series s where s.source = 'test.synth' and not exists (select 1 from ripples.att_zvec z where z.series_id = s.series_id)) then
      pre_common := exists (select 1 from ripples.att_common_days where day = t0);
      v_ev := ripples.att_library_event(null, 'Synthetic shock', 'test.synth', t0, 'library');
      select array_agg(e.event_id) into grp from ripples.att_events e where e.event_id = v_ev or e.matched_to = v_ev;
      st := st || jsonb_build_object('event_id', v_ev, 'group', to_jsonb(grp), 'common_pre', pre_common);
      stage := 'freeze';
    end if;
  -- ------------------------------------------------------------------------------------------------------------ freeze (att_run_library, front half)
  elsif stage = 'freeze' then
    for a in select distinct e.as_of from ripples.att_events e where e.event_id = any(grp) order by 1 loop
      fr := ripples.att_freeze_candidates(a, true, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = any(grp) and e.as_of = a));
    end loop;
    st := st || jsonb_build_object('freeze', fr - 'frozen_hash');
    stage := 'looks';
  -- ------------------------------------------------------------------------------------------------------------ looks, chunked (earliest look day first)
  elsif stage = 'looks' then
    for r in select c.hop_id, u.o look_no, u.d from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
             where c.event_id = any(grp) and c.frozen_hash is not null and c.status <> 'skipped' and u.d <= current_date
               and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'))
             order by u.d, (c.role = 'library') desc, c.hop_id loop
      exit when clock_timestamp() - tt > make_interval(secs => p_budget_s);
      perform ripples.att_engine_job(jsonb_build_object('hop_id', r.hop_id, 'look', r.look_no));
      n := n + 1;
    end loop;
    st := st || jsonb_build_object('looks_ran', coalesce((st ->> 'looks_ran')::int, 0) + n);
    if not exists (select 1 from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
                   where c.event_id = any(grp) and c.frozen_hash is not null and c.status <> 'skipped' and u.d <= current_date
                     and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'))) then
      stage := 'finalize';
    end if;
  -- ------------------------------------------------------------------------------------------------------------ finalize + T7 / T8 / T17
  elsif stage = 'finalize' then
    select max(l) into last_look from ripples.att_hop_candidates c, unnest(c.looks) l where c.event_id = any(grp) and c.frozen_hash is not null and l <= current_date;
    fin := ripples.att_finalize(last_look, true, false, grp);
    perform ripples.att_chain_decide(last_look);
    perform ripples.att_build_cascade(v_ev, last_look);
    st := st || jsonb_build_object('finalize', fin, 'final_day', last_look);
    select count(*) filter (where hl.tier = 'measured' and hl.node >= 'test.synth:s71'), count(*) filter (where hl.tier in ('likely','measured') and hl.node <= 'test.synth:s10')
      into n_inj_meas, n_null_likely from ripples.att_hop_latest hl where hl.event_id = v_ev;
    select count(*), count(*) filter (where hl.tier = 'measured') into n_decoy_tested, n_decoy_meas
      from ripples.att_hop_latest hl join ripples.att_events e on e.event_id = hl.event_id where e.matched_to = v_ev and e.role = 'decoy' and hl.t_stat is not null;
    if ripples._att_want(st, 'T7') then
      ok := n_inj_meas >= 8 and n_null_likely <= 1 and n_decoy_meas <= greatest(1, n_decoy_tested / 10);
      res := ripples._att_t(res, 'T7 synthetic fixture: injected targets Measured (recall ≥ 8/10), null targets flat, decoy Measured rate ≤ 0.10', ok,
               jsonb_build_object('injected_measured', n_inj_meas, 'null_likely_or_better', n_null_likely, 'decoy_tested', n_decoy_tested, 'decoy_measured', n_decoy_meas, 'finalize', fin,
                                  'nodes', (select jsonb_agg(jsonb_build_object('node', hl.node, 'tier', hl.tier, 'T', round(hl.t_stat::numeric, 2), 'p', hl.fluke, 'p_date', hl.p_date, 'n_date', hl.n_date, 'p_topic', hl.p_topic, 'n_topic', hl.n_topic, 'q', round(hl.q_w::numeric, 4), 'fails', hl.detail -> 'fails') order by hl.node)
                                            from ripples.att_hop_latest hl where hl.event_id = v_ev)));
    end if;
    select hl.hop_id, hl.look_no into v_hop, v_look from ripples.att_hop_latest hl where hl.event_id = v_ev and hl.t_stat is not null order by hl.t_stat desc limit 1;
    st := st || jsonb_build_object('hop', v_hop, 'look', v_look);
    if ripples._att_want(st, 'T8') then
      aa := ripples.att_test_hop(v_hop, v_look, null, null); bb := ripples.att_test_hop(v_hop, v_look, 'rival', v_ev::int);
      ok := abs((aa ->> 'T')::float8 - (bb ->> 'T')::float8) < 1e-9;
      res := ripples._att_t(res, 'T8 placebo draw at shift 0 equals the real statistic (identical code path)', ok, jsonb_build_object('T_real', aa ->> 'T', 'T_shift0', bb ->> 'T'));
    end if;
    if ripples._att_want(st, 'T17') then
      ok := not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'library' and (c.l_by_channel is null or c.engine_version not like '6.1%' or c.graph_version is null))
            and (select l_by_channel ->> 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop) = '7'
            and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role <> 'negative_control' group by c.as_of, c.event_id, c.parent_hop, c.node, c.sign having count(*) > 1)
            and not exists (select 1 from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id where c.event_id = v_ev and t.q_w is not null and t.look_no < 100
                            and abs((t.detail -> 'bh' ->> 'p_bh')::float8 - ripples.att_bh_input(t.p_date, t.n_date, t.p_topic, t.n_topic, t.p_link, t.n_link, t.fluke, coalesce((ripples._att_cfg('engine') ->> 'bh_min_draws')::int, 200))::float8) > 1e-6)
            and (select every(sign <> 0) from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'negative_control');
      res := ripples._att_t(res, 'T17 frozen L / versions on the batch, no duplicate paths, BH input = max over families with >= bh_min_draws draws (p_h fallback), signed negative controls', ok,
               (select jsonb_build_object('l_by_channel', l_by_channel, 'engine_version', engine_version, 'graph_version', left(graph_version, 12)) from ripples.att_hop_candidates where hop_id = v_hop));
    end if;
    stage := 'chain';
    st := st || jsonb_build_object('i', 0, 'ps', '[]'::jsonb);
  -- ------------------------------------------------------------------------------------------------------------ T50–T52: chaining record (6.1.2)
  elsif stage = 'chain' then
    if ripples._att_want(st, 'T50') or ripples._att_want(st, 'T51') or ripples._att_want(st, 'T52') then
      -- the parent: the fixture hop for s71 (an injected series); two synthetic depth-2 children with onset = the parent's movement onset
      select c.hop_id, coalesce(t.t_v, c.onset) as onset_v into r from ripples.att_hop_candidates c
        join lateral (select t_v from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.t_stat is not null order by look_no desc limit 1) t on true
       where c.event_id = v_ev and c.node = 'test.synth:s71' limit 1;
      v_hop := r.hop_id; last_look := r.onset_v;
      perform ripples.att_node_bundle('test.synth:s81'); perform ripples.att_node_bundle('test.synth:s82');
      for i in 81..82 loop
        insert into ripples.att_hop_candidates(as_of, u_topic, v_topic, proposed_by, edge, status, event_id, role, parent_hop, depth, path, path_type, prior, bh_weight, channels, excluded_ch,
                                               window_close, looks, voi, node, onset, sign, reconstructed, frozen_hash, frozen_at, freeze_proven, engine_version, l_by_channel)
        select c.as_of, c.u_topic, c.v_topic, c.proposed_by, c.edge, 'queued', c.event_id, 'library', v_hop, 2,
               jsonb_build_array(jsonb_build_object('type', 'MECH', 'from', 'test.synth:s71', 'to', 'test.synth:s' || i, 'sign', 1, 's', 1.0, 'source', 'test chain')), 'P-MECH', c.prior, c.bh_weight, c.channels, c.excluded_ch,
               last_look + 7, array[last_look + 8], c.voi, 'test.synth:s' || i, last_look, 1, true, 'test-chain-' || v_hop || '-' || i, now(), false, '6.1', c.l_by_channel
        from ripples.att_hop_candidates c where c.hop_id = v_hop returning hop_id into v_child;
        perform ripples.att_engine_job(jsonb_build_object('hop_id', v_child, 'look', 1));
        st := st || jsonb_build_object('chain_' || i, (select t.detail -> 'chain' from ripples.att_hop_tests t where t.hop_id = v_child and t.look_no = 1));
      end loop;
      perform ripples.att_build_cascade(v_ev, last_look + 8);
      j := st -> 'chain_81'; j2 := st -> 'chain_82';
      ok := j is not null and (j ->> 'order_ok')::boolean and (j ->> 'lag_parent_child_days')::int between 1 and 4 and (j ->> 'beta')::float8 > 0.2 and (j ->> 'p')::float8 <= 0.05
            and not (j ->> 'fork_test')::boolean and (j ->> 'mediation_c')::boolean and (j ->> 'attenuation')::float8 >= 0.5;
      res := ripples._att_t(res, 'T50 mediated child (s81 = 0.6·s71 two days later): order ok, β > 0 with p ≤ 0.05, attenuation ≥ 0.5 → fork_test false, mediation_c true', ok, j);
      ok := j2 is not null and ((j2 ->> 'fork_test')::boolean or not (j2 ->> 'mediation_c')::boolean) and coalesce((j2 ->> 'beta')::float8, 0) < 0.2;
      res := ripples._att_t(res, 'T51 independent child (s82 moves with the event, no s71 → s82 association): stays a fork', ok, j2);
      ok := exists (select 1 from ripples.att_hop_tests t where t.hop_id = v_hop and t.t_stat is not null and t.detail ? 'lag_days' and t.detail ? 'lag_from_event_days'
                    and (t.detail ->> 'lag_from_event_days')::int = t.t_v - t0)
            and exists (select 1 from ripples.att_cascades cs, jsonb_array_elements(cs.payload -> 'nodes') nd where cs.event_id = v_ev and nd ? 'lag_days' and nd ? 'lag_from_event_days' and nd ? 'chain');
      res := ripples._att_t(res, 'T52 lag_days / lag_from_event_days on test rows and cascade nodes; cascade nodes carry the chain record', ok,
               jsonb_build_object('parent', (select jsonb_build_object('lag_days', t.detail -> 'lag_days', 'lag_from_event_days', t.detail -> 'lag_from_event_days', 't_v', t.t_v) from ripples.att_hop_tests t where t.hop_id = v_hop and t.t_stat is not null order by look_no desc limit 1)));
    end if;
    stage := case when ripples._att_want(st, 'T7') then 'heldout' else 'reexam' end;
  -- ------------------------------------------------------------------------------------------------------------ held-out null p-values, chunked
  elsif stage = 'heldout' then
    i := coalesce((st ->> 'i')::int, 0);
    while i < 50 and clock_timestamp() - tt < make_interval(secs => p_budget_s) loop
      i := i + 1;
      select series_id into v_sid from ripples.att_series where source = 'test.synth' and key = 's' || lpad(i::text, 2, '0');
      j := ripples.att_heldout_p(v_sid, t0, t0 + 7, 200);
      if (j ->> 'p') is not null then st := st || jsonb_build_object('ps', (st -> 'ps') || to_jsonb((j ->> 'p')::float8)); end if;
    end loop;
    st := st || jsonb_build_object('i', i);
    if i >= 50 then
      select array_agg(x::float8) into ps from jsonb_array_elements_text(st -> 'ps') x;
      ks := ripples.att_ks_uniform(ps);
      ok := (ks ->> 'p')::float8 >= 0.05 and (select min(x) from unnest(ps) x) >= 1::float8 / 201 - 1e-12;
      res := ripples._att_t(res, 'T7 null p-values uniform (KS p ≥ 0.05) and floored at 1/(N+1)', ok, ks - 'hist' || jsonb_build_object('min_p', (select min(x) from unnest(ps) x), 'n', cardinality(ps)));
      stage := 'reexam';
    end if;
  -- ------------------------------------------------------------------------------------------------------------ T9 re-examination + T10–T12
  elsif stage = 'reexam' then
    v_hop := (st ->> 'hop')::bigint; v_look := (st ->> 'look')::smallint;
    if ripples._att_want(st, 'T9') and v_hop is not null then
      insert into ripples.att_hop_registry(hop_id, window_close, p_hat, family, path_type, channel) select v_hop, window_close, 0.2, 'test.synth', path_type, 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop
      on conflict (hop_id) do nothing;
      update ripples.att_hop_registry set published_tier = 'measured', published_at = now() where hop_id = v_hop;
      v_q_before := (select q_w from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look);
      insert into ripples.att_hop_candidates(as_of, u_topic, v_topic, proposed_by, edge, status, event_id, role, parent_hop, depth, path, path_type, prior, bh_weight, channels, excluded_ch,
                                             window_close, looks, voi, node, onset, sign, reconstructed, frozen_hash, frozen_at, freeze_proven, engine_version)
      select c.as_of, c.u_topic, c.v_topic, c.proposed_by, c.edge, 'tested', c.event_id, 'library', v_hop, 2, c.path, c.path_type, c.prior, c.bh_weight, c.channels, c.excluded_ch,
             c.window_close + 7, array[c.window_close + 8], c.voi, c.node, c.onset + 7, c.sign, true, 'test-child-' || v_hop, now(), false, '6.1'
      from ripples.att_hop_candidates c where c.hop_id = v_hop returning hop_id into v_child;
      insert into ripples.att_hop_tests(hop_id, look_no, as_of, u_topic, v_topic, t_u, look_day, is_final, t_stat, fluke, q_w, tier, tier_reason, flags, detail)
      select v_child, 1, c.as_of, c.u_topic, c.v_topic, c.onset, c.looks[1], true, 4.0, 0.02, 0.05, 'likely', 'test child', '{}', '{"n_out3": 1}'::jsonb
      from ripples.att_hop_candidates c where c.hop_id = v_child;
      insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
      select c.onset, '{}', '{}'::jsonb, 'registered', current_date from ripples.att_hop_candidates c where c.hop_id = v_hop
      on conflict (day) do update set reason = 'registered';
      fin := ripples.att_reexamine(current_date, true, p_budget_s);
      ok := (select tier from ripples.att_hop_tests where hop_id = v_hop and look_no >= 100 order by look_no desc limit 1) = 'retracted'
            and (select q_w from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look) = v_q_before and v_q_before is not null
            and (select tier from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look) <> 'retracted'
            and exists (select 1 from ripples.att_ledger where kind = 'retract' and (ref ->> 'hop_id')::bigint = v_hop)
            and (select tier from ripples.att_hop_tests where hop_id = v_child order by look_no desc limit 1) = 'retracted'
            and (select tier_reason from ripples.att_hop_tests where hop_id = v_child order by look_no desc limit 1) = 'previous step retracted'
            and exists (select 1 from ripples.att_ledger where kind = 'retract' and (ref ->> 'hop_id')::bigint = v_child);
      res := ripples._att_t(res, 'T9 settled-hop re-examination retracts on a later common-shock flag without touching the settled look; the retraction propagates to the child', ok,
               jsonb_build_object('reexam', fin - 'finalize', 'tier_new', (select tier from ripples.att_hop_tests where hop_id = v_hop and look_no >= 100 order by look_no desc limit 1),
                                  'reason', (select retract_reason from ripples.att_hop_tests where hop_id = v_hop and look_no >= 100 order by look_no desc limit 1),
                                  'q_settled_before', v_q_before, 'q_settled_after', (select q_w from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look),
                                  'child_tier', (select tier from ripples.att_hop_tests where hop_id = v_child order by look_no desc limit 1)));
      st := st || jsonb_build_object('child', v_child);
    end if;
    if ripples._att_want(st, 'T10') then
      lv := ripples.att_ledger_verify(); ledger_ok := (lv ->> 'ok')::boolean;
      begin
        update ripples.att_ledger set payload_hash = repeat('0', 64) where seq = (select min(seq) from ripples.att_ledger where kind = 'freeze');
        tamper := ripples.att_ledger_verify();
        raise exception 'rollback tamper';
      exception when others then null; end;
      ok := ledger_ok and not (tamper ->> 'ok')::boolean and jsonb_array_length(tamper -> 'bad') >= 1;
      res := ripples._att_t(res, 'T10 ledger chain verifies; a tampered freeze row is detected', ok, jsonb_build_object('verify', lv - 'bad', 'tamper_bad', tamper -> 'bad'));
    end if;
    if ripples._att_want(st, 'T11') then
      ok := not exists (select 1 from ripples.att_hop_tests where fluke is not null and p_floor is not null and fluke < p_floor - 1e-9)
            and not exists (select 1 from ripples.att_hop_tests where tier = 'measured' and coalesce((detail ->> 'n_out3')::int, 0) < 1);
      res := ripples._att_t(res, 'T11 p-value floors respected; every Measured row has an outcome channel', ok, null);
    end if;
    if ripples._att_want(st, 'T12') then
      select coalesce(jsonb_agg(distinct pk), '[]'::jsonb) into bad_keys
        from ripples.att_cascades c, jsonb_path_query(c.payload, 'strict $.**') p, jsonb_object_keys(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) pk
       where pk ~* 'chain_?(prob|f|cred)|compound|prob_true';
      ok := jsonb_array_length(bad_keys) = 0 and not exists (select 1 from ripples.att_cascades c where c.payload::text ~* '\m(caused|drove|because of)\M');
      res := ripples._att_t(res, 'T12 no payload contains a chain probability or a causal claim', ok, jsonb_build_object('bad_keys', bad_keys));
    end if;
    stage := 'cleanup';
  -- ------------------------------------------------------------------------------------------------------------ cleanup: every fixture row goes; ledger rows are marked
  elsif stage = 'cleanup' then
    if grp is not null then
      select array_agg(c.hop_id), array_agg(distinct c.frozen_hash) filter (where c.frozen_hash not like 'test-child-%' and c.frozen_hash not like 'test-chain-%') into ids, hashes from ripples.att_hop_candidates c where c.event_id = any(grp);
      delete from ripples.att_placebo_top where hop_id = any(ids);
      delete from ripples.att_placebo_draws where hop_id = any(ids);
      delete from ripples.att_hop_tests where hop_id = any(ids);
      delete from ripples.att_hop_registry where hop_id = any(ids);
      delete from ripples.att_hop_candidates where hop_id = any(ids);
      update ripples.att_ledger set ref = ref || jsonb_build_object('superseded_by', 'fixture-cleanup') where kind = 'freeze' and payload_hash = any(hashes);
      delete from ripples.att_cascades where event_id = any(grp);
      delete from ripples.att_events where event_id = any(grp);
      delete from ripples.att_topics where label_key like 'decoy:' || v_ev || ':%' or label_key = 'library:' || ripples.att_slugify('Synthetic shock') || ':' || t0;
      if not coalesce((st ->> 'common_pre')::boolean, false) then delete from ripples.att_common_days where day = t0 and reason = 'registered'; end if;
    end if;
    delete from ripples.att_sd_null where series_id in (select series_id from ripples.att_series where source = 'test.synth');
    delete from ripples.att_zvec where series_id in (select series_id from ripples.att_series where source = 'test.synth');
    delete from ripples.attention_obs where series_id in (select series_id from ripples.att_series where source = 'test.synth');
    delete from ripples.att_zvec_ct where source = 'test.synth';
    delete from ripples.att_node_series where node like 'test.synth:%';
    delete from ripples.att_series where source = 'test.synth';
    delete from ripples.att_families where family = 'test.synth';
    delete from ripples.att_engine_source_map where source = 'test.synth';
    delete from ripples.att_sources where source = 'test.synth';
    perform ripples.att_state_set('engine.test', jsonb_build_object('ok', not exists (select 1 from jsonb_array_elements(res) r where not (r ->> 'ok')::boolean), 'tests', res, 'at', now(),
                                  'staged', true, 'started', st -> 'started', 'calls', coalesce((st ->> 'calls')::int, 0) + 1,
                                  'seconds', round((coalesce((st ->> 'seconds')::numeric, 0) + extract(epoch from clock_timestamp() - tt))::numeric, 1), 'only', st -> 'only'));
    perform ripples.att_state_set('engine.test.request', jsonb_build_object('status', 'done', 'at', now(), 'staged', true));
    stage := 'finished';
    perform cron.unschedule('att-test-step') from cron.job where jobname = 'att-test-step';
  end if;
  exception when others then
    get stacked diagnostics ctx = pg_exception_context;
    st := st || jsonb_build_object('stage', 'failed', 'failed_in', stage, 'error', sqlerrm, 'state', sqlstate, 'ctx', left(ctx, 600), 'at', now(), 'res', res);
    perform ripples.att_state_set('engine.test.stage', st);
    perform ripples.att_state_set('engine.test', jsonb_build_object('error', sqlerrm, 'state', sqlstate, 'failed_in', stage, 'ctx', left(ctx, 600), 'tests', res, 'at', now(), 'staged', true));
    perform ripples.att_state_set('engine.test.request', jsonb_build_object('status', 'failed', 'at', now(), 'staged', true));
    perform pg_advisory_unlock(hashtext('ripples.att_test_step'));
    return st - 'res';
  end;
  st := st || jsonb_build_object('stage', stage, 'res', res, 'calls', coalesce((st ->> 'calls')::int, 0) + 1,
                                 'seconds', round((coalesce((st ->> 'seconds')::numeric, 0) + extract(epoch from clock_timestamp() - tt))::numeric, 1), 'at', now(), 'this_call', n);
  if stage = 'finished' then st := st || jsonb_build_object('finished', now()); end if;
  perform ripples.att_state_set('engine.test.stage', st);
  perform pg_advisory_unlock(hashtext('ripples.att_test_step'));
  return st - 'res' - 'ps';
end $$;
revoke all on function ripples.att_test_step(int) from anon, authenticated, public;
revoke all on function ripples._att_want(jsonb, text) from anon, authenticated, public;

-- Group-scoped look runner: pending looks of ONE event group (event + decoys + negatives), earliest look day first, within a budget.
-- att_engine_run_due(day, …, reconstructed) ran every pending reconstructed look of a day, so a positive control, the harness fixture and
-- the cron recompute could all touch the same hops at once (deadlock 40P01 at 04:36 UTC on att_hop_candidates.status). Each runner now
-- keeps to its own group; the recompute keeps to the events of its own group list.
create or replace function ripples.att_engine_run_group(p_events bigint[], p_as_of date, p_budget_s int default 100000) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; t0 timestamptz := clock_timestamp(); left_over int := 0;
begin
  for r in
    select c.hop_id, u.o look_no, u.d
    from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
    where c.event_id = any(p_events) and c.frozen_hash is not null and c.status <> 'skipped' and u.d <= p_as_of
      and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'))
    order by u.d, (c.role in ('real','library','positive_control')) desc, c.voi desc nulls last, c.hop_id
  loop
    if clock_timestamp() - t0 > make_interval(secs => p_budget_s) then left_over := left_over + 1; continue; end if;
    perform ripples.att_engine_job(jsonb_build_object('hop_id', r.hop_id, 'look', r.look_no));
    n := n + 1;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'ran', n, 'left_over', left_over, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;
revoke all on function ripples.att_engine_run_group(bigint[], date, int) from anon, authenticated, public;

-- Chunked library runner: one event group (event + its decoys + negatives) advanced in ≤ budget-second steps — decoys, freeze of every
-- unfrozen day, pending looks earliest-day-first. Returns done = true when no look is pending; the caller then finalizes (att_run_library
-- on a fully-looked group is seconds: freeze skips, no looks run, finalize scores the group). Used by the deploy gate so a positive
-- control never holds pg_cron for more than one chunk.
create or replace function ripples.att_library_step(p_event bigint, p_budget_s int default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev record; grp bigint[]; a date; r jsonb; t0 timestamptz := clock_timestamp(); n_pend int; e2 record; n_dec int := 0;
begin
  select * into ev from ripples.att_events where event_id = p_event and reconstructed;
  if not found then return jsonb_build_object('error', 'not a reconstructed event', 'done', true); end if;
  -- same as att_run_library: an event registered after its day was frozen moves to the next unfrozen day
  if exists (select 1 from ripples.att_hop_candidates c where c.as_of = ev.as_of and c.frozen_hash is not null)
     and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = p_event) then
    a := ev.as_of + 1;
    while exists (select 1 from ripples.att_hop_candidates c where c.as_of = a and c.frozen_hash is not null) loop a := a + 1; end loop;
    update ripples.att_events set as_of = a where event_id = p_event;
    ev.as_of := a;
  end if;
  for e2 in select event_id from ripples.att_events where reconstructed and role in ('library','positive_control') and as_of = ev.as_of loop
    n_dec := n_dec + ripples.att_library_decoys(e2.event_id);
  end loop;
  select array_agg(e.event_id) into grp from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event;
  for a in select distinct e.as_of from ripples.att_events e where e.event_id = any(grp)
             and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = e.event_id and c.frozen_hash is not null) order by 1 loop
    perform ripples.att_freeze_candidates(a, true, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = any(grp) and e.as_of = a));
  end loop;
  r := ripples.att_engine_run_group(grp, current_date, p_budget_s);
  select count(*) into n_pend from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
   where c.event_id = any(grp) and c.frozen_hash is not null and c.status <> 'skipped' and u.d <= current_date
     and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'));
  return jsonb_build_object('event_id', p_event, 'group', cardinality(grp), 'decoys_created', n_dec, 'ran', r -> 'ran', 'pending', n_pend, 'done', n_pend = 0,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;
revoke all on function ripples.att_library_step(bigint, int) from anon, authenticated, public;

-- Deploy gate as chunks: each call advances ONE positive control by ≤ budget s; when its looks are complete the control is scored
-- (att_run_positive_control → att_run_library, seconds on a fully-looked group); when every positive has run today the negative
-- check + ledger 'control' row follow (att_run_controls, seconds). Progress in att_state 'engine.controls.request'.
create or replace function ripples.att_controls_step(p_budget_s int default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare req jsonb := coalesce(ripples.att_state_get('engine.controls.request'), '{}'::jsonb); k record; r jsonb; ctx text; t0 timestamptz := clock_timestamp(); ev bigint; ls jsonb;
begin
  if coalesce(req ->> 'status', '') <> 'pending' then return jsonb_build_object('idle', true); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_controls_runner')) then return jsonb_build_object('skipped', 'running'); end if;
  begin
    select * into k from ripples.att_controls where kind = 'positive' and (last_run is null or last_run < current_date) order by id limit 1;
    if found then
      if k.spec ? 'slug' then select event_id into ev from ripples.att_events where slug = k.spec ->> 'slug' and role = 'positive_control'; end if;
      if ev is null then ev := ripples.att_library_event(k.spec ->> 'qid', k.spec ->> 'label', k.spec ->> 'family', (k.spec ->> 'onset')::date, 'positive_control', k.spec -> 'meta'); end if;
      if k.spec ? 'meta' then update ripples.att_topics t set meta = coalesce(t.meta, '{}'::jsonb) || (k.spec -> 'meta') where t.topic_id = (select topic_id from ripples.att_events where event_id = ev); end if;
      ls := ripples.att_library_step(ev, p_budget_s);
      if (ls ->> 'done')::boolean then
        r := ripples.att_run_positive_control(k.id);
        perform ripples.att_state_set('engine.controls.request', req || jsonb_build_object('last', r - 'event_id', 'at', now(), 'progress', null));
      else
        perform ripples.att_state_set('engine.controls.request', req || jsonb_build_object('progress', jsonb_build_object('control', k.id, 'name', k.spec ->> 'name') || ls, 'at', now()));
        r := ls;
      end if;
    else
      r := ripples.att_run_controls(false);
      perform ripples.att_state_set('engine.controls', r || jsonb_build_object('at', now(), 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
      perform ripples.att_state_set('engine.controls.request', jsonb_build_object('status', 'done', 'at', now()));
    end if;
  exception when others or query_canceled then
    get stacked diagnostics ctx = pg_exception_context;
    perform ripples.att_state_set('engine.controls', jsonb_build_object('error', sqlerrm, 'state', sqlstate, 'ctx', left(ctx, 800), 'at', now(), 'control', k.id));
    perform ripples.att_state_set('engine.controls.request', jsonb_build_object('status', 'failed', 'at', now(), 'control', k.id));
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_controls_runner'));
  return coalesce(r, '{}'::jsonb) - 'positive';
end $$;
revoke all on function ripples.att_controls_step(int) from anon, authenticated, public;
drop function if exists ripples.att_controls_step();

-- ---------------------------------------------------------------------------------------------------------------------
-- Chaining record for child hops (ENGINE §4.2–4.4; engine 6.1.2). Written by att_engine_job at every look of a depth ≥ 2 hop as
-- att_hop_tests.detail -> 'chain' = {fork_test, mediation_c, order_ok, lag_parent_child_days, method, p, …}. The story layer draws a
-- CHAIN edge parent → child only when fork_test = false AND mediation_c = true; anything unsure stays a fork.
--   order_ok            event onset ≤ parent movement onset ≤ child movement onset ≤ parent onset + 60 d
--   association (β, p)  child AR(t) regressed on parent AR(t − lag) over the pre-onset year (windows ending ≥ 30 d before the parent's
--                       onset, ≥ 120 pairs); p from 40 block-shift placebos of the parent series (shifts of 28 … 308 d) — the
--                       "residual parent → child association" the fork test asks for
--   fork_test           TRUE (= fork) unless order_ok, β > 0 with p ≤ 0.05, and the event's direct candidate for the same node (the
--                       depth-1 or fork-check hop) did not move BEFORE the parent did. No data / no series / too short → fork.
--   mediation_c         order_ok, β > 0, and the child's own window statistic falls by ≥ 50 % once β · parent AR(t − lag) is
--                       subtracted (Baron–Kenny step c: the child's event-window move is carried by the parent's movement)
-- Nothing here changes a tier: the record only feeds the fork_of / chain labels and the story layer.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_chain_check(p_hop bigint, p_look smallint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; p record; t record; pt record; fk record; ev_onset date; parent_onset date; child_onset date; lag int; order_ok boolean;
        best jsonb; pbest jsonb; cs bigint; ps bigint; zc record; zp record; kind text; l int; sgn int;
        i int; jx int; d date; sxy float8 := 0; sxx float8 := 0; n_pairs int := 0; beta float8; a float8; b float8;
        k int; sh int; bk float8; ex int := 0; nd int := 0; p_assoc float8; ar_res real[]; s0 jsonb; s1 jsonb; v0 float8; v1 float8; att float8;
        v_fork boolean; v_med boolean; direct_earlier boolean; t_lo date; t_hi date; ilo int; ihi int; rho float8;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  if not found or c.depth < 2 or c.parent_hop is null then return null; end if;
  select * into t from ripples.att_hop_tests where hop_id = p_hop and look_no = p_look;
  select * into p from ripples.att_hop_candidates where hop_id = c.parent_hop;
  select * into pt from ripples.att_hop_tests t2 where t2.hop_id = c.parent_hop and t2.t_stat is not null and t2.look_no < 100 order by t2.look_no desc limit 1;
  select onset into ev_onset from ripples.att_events where event_id = c.event_id;
  parent_onset := coalesce(pt.t_v, p.onset); child_onset := coalesce(t.t_v, c.onset);
  lag := child_onset - parent_onset;
  order_ok := ev_onset <= parent_onset and lag >= 0 and lag <= 60;
  -- the event's direct candidate for the same node (depth-1 real/decoy or the fork check staged by att_expand)
  select c1.hop_id, t1.t_stat, t1.t_v into fk from ripples.att_hop_candidates c1
    left join lateral (select * from ripples.att_hop_tests t1 where t1.hop_id = c1.hop_id and t1.t_stat is not null and t1.look_no < 100 order by look_no desc limit 1) t1 on true
   where c1.event_id = c.event_id and c1.depth = 1 and c1.node = c.node and c1.role in ('real','decoy','library','positive_control','fork_check') order by (t1.t_stat is not null) desc limit 1;
  direct_earlier := fk.t_v is not null and fk.t_v < parent_onset;
  -- series: the best agreeing channel's series on each side (else the node's best daily series)
  select v into best from jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) e(k, v) order by (v ->> 'zhat')::float8 desc nulls last limit 1;
  select v into pbest from jsonb_each(coalesce(pt.s_by_channel, '{}'::jsonb)) e(k, v) order by (v ->> 'zhat')::float8 desc nulls last limit 1;
  cs := (best ->> 'best_series')::bigint; ps := (pbest ->> 'best_series')::bigint;
  if cs is null then select ns.series_id into cs from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id and z.grain = 'day' where ns.node = c.node order by z.kappa desc limit 1; end if;
  if ps is null then select ns.series_id into ps from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id and z.grain = 'day' where ns.node = p.node order by z.kappa desc limit 1; end if;
  if cs is null or ps is null or cs = ps then
    return jsonb_build_object('fork_test', true, 'mediation_c', false, 'order_ok', order_ok, 'lag_parent_child_days', lag, 'method', 'no series pair', 'p', null,
                              'parent_hop', c.parent_hop, 'parent_onset', parent_onset, 'child_onset', child_onset, 'direct_hop', fk.hop_id, 'direct_earlier', direct_earlier);
  end if;
  select from_day, n, ar into zc from ripples.att_zvec where series_id = cs and grain = 'day';
  select from_day, n, ar into zp from ripples.att_zvec where series_id = ps and grain = 'day';
  kind := coalesce(best ->> 'stat', 'car'); l := coalesce((best ->> 'l')::int, 7); sgn := coalesce(c.sign, 1);
  -- pre-onset association: child AR(t) on parent AR(t − lag), t in [parent_onset − 395, parent_onset − 30]
  t_lo := greatest(parent_onset - 395, zc.from_day + 1, zp.from_day + lag + 1); t_hi := parent_onset - 30;
  d := t_lo;
  while d <= t_hi loop
    i := (d - zc.from_day) + 1; jx := (d - lag - zp.from_day) + 1;
    if i >= 1 and i <= zc.n and jx >= 1 and jx <= zp.n then
      a := zc.ar[i]; b := zp.ar[jx];
      if a is not null and b is not null then sxy := sxy + a * b; sxx := sxx + b * b; n_pairs := n_pairs + 1; end if;
    end if;
    d := d + 1;
  end loop;
  if n_pairs < 120 or sxx <= 0 then
    return jsonb_build_object('fork_test', true, 'mediation_c', false, 'order_ok', order_ok, 'lag_parent_child_days', lag, 'method', 'pre-onset pairs < 120', 'p', null, 'n', n_pairs,
                              'parent_hop', c.parent_hop, 'parent_onset', parent_onset, 'child_onset', child_onset, 'direct_hop', fk.hop_id, 'direct_earlier', direct_earlier, 'series', jsonb_build_array(ps, cs));
  end if;
  beta := sxy / sxx;
  -- block-shift placebos of the parent series (28 … 308 d): the residual association must beat what an unrelated alignment gives
  for k in 1..40 loop
    sh := 28 + 7 * (k - 1); bk := 0; sxx := 0; d := t_lo;
    while d <= t_hi loop
      i := (d - zc.from_day) + 1; jx := (d - lag - sh - zp.from_day) + 1;
      if i >= 1 and i <= zc.n and jx >= 1 and jx <= zp.n then
        a := zc.ar[i]; b := zp.ar[jx];
        if a is not null and b is not null then bk := bk + a * b; sxx := sxx + b * b; end if;
      end if;
      d := d + 1;
    end loop;
    if sxx > 0 then nd := nd + 1; if bk / sxx >= beta then ex := ex + 1; end if; end if;
  end loop;
  p_assoc := case when nd = 0 then null else (1 + ex)::float8 / (1 + nd) end;
  -- mediation (c): the child's window statistic with β · parent AR(t − lag) removed
  ar_res := zc.ar;
  ilo := greatest(1, (child_onset - zc.from_day) + 1 - 7); ihi := least(zc.n, (child_onset - zc.from_day) + 1 + l + 7);
  for i in ilo..ihi loop
    jx := (i - 1 + zc.from_day - lag - zp.from_day) + 1;
    if ar_res[i] is not null and jx >= 1 and jx <= zp.n and zp.ar[jx] is not null then ar_res[i] := (ar_res[i] - beta * zp.ar[jx])::real; end if;
  end loop;
  rho := case when kind = 'car' then ripples.att_rho1(zc.ar, zc.from_day, zc.n, child_onset) else 0 end;
  s0 := ripples.att_win_stat(zc.ar,  null, zc.from_day, zc.n, child_onset, l, kind, sgn, rho, zc.from_day + zc.n - 1, false);
  s1 := ripples.att_win_stat(ar_res, null, zc.from_day, zc.n, child_onset, l, kind, sgn, rho, zc.from_day + zc.n - 1, false);
  v0 := (s0 ->> 'S')::float8; v1 := (s1 ->> 'S')::float8;
  att := case when v0 is not null and v0 > 0 and v1 is not null then 1 - greatest(v1, 0) / v0 end;
  v_med := order_ok and beta > 0 and coalesce(att, 0) >= 0.5;
  v_fork := not (order_ok and beta > 0 and coalesce(p_assoc, 1) <= 0.05 and not direct_earlier);
  return jsonb_build_object('fork_test', v_fork, 'mediation_c', v_med, 'order_ok', order_ok, 'lag_parent_child_days', lag,
                            'method', 'pre-onset lagged regression of child AR on parent AR (≥ 120 d) + 40 block-shift placebos; mediation = window statistic attenuation ≥ 0.5 after removing β·parent',
                            'p', round(p_assoc::numeric, 4), 'beta', round(beta::numeric, 4), 'n', n_pairs, 'attenuation', round(att::numeric, 3), 'S_child', round(v0::numeric, 3), 'S_resid', round(v1::numeric, 3),
                            'parent_hop', c.parent_hop, 'parent_onset', parent_onset, 'child_onset', child_onset, 'direct_hop', fk.hop_id, 'direct_t', fk.t_stat, 'direct_earlier', direct_earlier,
                            'series', jsonb_build_array(ps, cs), 'stat', kind, 'l', l);
end $$;
revoke all on function ripples.att_chain_check(bigint, smallint) from anon, authenticated, public;

-- att_chain_decide: the same record decides fork_of (order violation → common cause stays as before)
create or replace function ripples.att_chain_decide(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; t_u date; t_v date; t_w date; pc jsonb;
begin
  for r in
    select c.hop_id, c.event_id, c.parent_hop, c.node, c.path, t.look_no, t.t_stat, t.lag_days, t.t_v, t.tier
    from ripples.att_hop_candidates c join ripples.att_hop_tests t on t.hop_id = c.hop_id
    where c.depth >= 2 and t.look_day = p_as_of and t.tier in ('likely','measured')
  loop
    select onset into t_u from ripples.att_events where event_id = r.event_id;
    select t2.t_v into t_v from ripples.att_hop_tests t2 where t2.hop_id = r.parent_hop and t2.tier is not null order by look_no desc limit 1;
    t_w := r.t_v;
    if t_v is not null and t_w is not null and not (t_u <= t_v and t_v <= t_w) then
      update ripples.att_hop_tests t set tier = 'flat', tier_reason = 'common cause (order violated)', detail = coalesce(t.detail, '{}'::jsonb) || '{"common_cause": true}'::jsonb
       where t.hop_id = r.hop_id and t.look_no = r.look_no;
      n := n + 1; continue;
    end if;
    pc := ripples.att_chain_check(r.hop_id, r.look_no);
    update ripples.att_hop_tests t set detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('chain', pc,
             'fork_of', case when coalesce((pc ->> 'fork_test')::boolean, true) or not coalesce((pc ->> 'mediation_c')::boolean, false) then to_jsonb(r.event_id) else 'null'::jsonb end)
     where t.hop_id = r.hop_id and t.look_no = r.look_no;
    n := n + 1;
  end loop;
  return n;
end $$;
