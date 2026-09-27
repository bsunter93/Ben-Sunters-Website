-- Unit + fixture tests for the Ripple Map cascade engine (WS-B). Run: select ripples.att_test_engine();  (service_role)
-- Covers: transforms (Φ, Φ⁻¹, NB mid-p, holidays), window statistic and CAR scaling, sd_null (6.1: robust pre-onset, degenerate exclusion), weighted BH (pure), frozen BH weights and
-- the bit-identical freeze hash, tier logic on a synthetic fixture with known injected effects (recall, null uniformity, decoy FDR),
-- attention-only cap, MONEY/IO zero tests, placebo shift-0 identity, settled-hop re-examination + propagation (T9), ledger chaining (incl. a tamper
-- check in a savepoint), holidays as common days (T14), geo filters (T15), frozen L (T16), batch versions / dedupe / BH input (T17), the Thanksgiving-week storm stop case (T18).
-- The synthetic fixture lives in source 'test.synth' (tier 'test') inside a sub-transaction that is rolled back at the end unless p_cleanup = false.

-- pure weighted BH (Genovese–Roeder–Wasserman): q_(i) = min_{j ≥ i} m · p_(j) / (w_(j) · j), clamped to 1; returned in input order
create or replace function ripples.att_bh_q(p_p float8[], p_w float8[]) returns float8[]
language sql immutable set search_path = '' as $$
  with x as (select p, w, o, p / w pw from unnest(p_p, p_w) with ordinality u(p, w, o)),
  r as (select o, pw, row_number() over (order by pw, o) rk, count(*) over () m from x),
  q as (select o, least(1, min(m * pw / rk) over (order by rk desc rows between unbounded preceding and current row)) q from r)
  select array_agg(q order by o) from q
$$;
revoke all on function ripples.att_bh_q(float8[], float8[]) from anon, authenticated, public;

create or replace function ripples._att_t(p_res jsonb, p_name text, p_ok boolean, p_detail jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select p_res || jsonb_build_object('test', p_name, 'ok', coalesce(p_ok, false), 'detail', p_detail)
$$;

drop function if exists ripples.att_test_engine(boolean);
create or replace function ripples.att_test_engine(p_cleanup boolean default true, p_only text[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare res jsonb := '[]'::jsonb; ok boolean; j jsonb; arr real[]; s jsonb; s2 jsonb; q float8[]; t0 date := current_date - 45; i int; k int;
        v_ev bigint; run jsonb; n_inj_meas int; n_null_likely int; n_decoy_meas int; n_decoy_tested int; ps float8[] := '{}';
        ks jsonb; v_hop bigint; v_look smallint; a jsonb; b jsonb; lv jsonb; h record; fin jsonb; ledger_ok boolean; tamper jsonb;
        v_sid bigint; nser int := 80; v_recomp text; bad_keys jsonb;
        v_q_before real; v_child bigint; j2 jsonb; j3 jsonb; v_ev2 bigint; run2 jsonb; v_topic2 bigint; n_meas2 int; n_tested2 int; v_sub record;
begin
  -- T1 transforms
  ok := abs(ripples.att_norm_inv(0.975) - 1.959964) < 1e-4 and abs(ripples.att_norm_cdf(1.96) - 0.9750021) < 1e-5
        and abs(ripples.att_norm_cdf(ripples.att_norm_inv(0.001)) - 0.001) < 1e-6;
  res := ripples._att_t(res, 'T1 normal cdf/quantile', ok, jsonb_build_object('inv975', ripples.att_norm_inv(0.975), 'cdf196', ripples.att_norm_cdf(1.96)));
  ok := abs(ripples.att_nb_midp_z(5, 5, null)) < 0.25 and ripples.att_nb_midp_z(15, 5, null) > 3 and ripples.att_nb_midp_z(15, 5, 2) < ripples.att_nb_midp_z(15, 5, null)
        and ripples.att_nb_midp_z(5000, 3, null) > 6;
  res := ripples._att_t(res, 'T1 NB mid-p z (Poisson centre, tail, overdispersion, underflow)', ok,
           jsonb_build_object('z_5_5', ripples.att_nb_midp_z(5, 5, null), 'z_15_5', ripples.att_nb_midp_z(15, 5, null), 'z_15_5_r2', ripples.att_nb_midp_z(15, 5, 2), 'z_5000_3', ripples.att_nb_midp_z(5000, 3, null)));
  ok := ripples.att_holiday('2025-11-27') = 'us_thanksgiving' and ripples.att_holiday('2025-12-25') = 'us_xmas' and ripples.att_holiday('2025-12-27') = 'xmas_week' and ripples.att_holiday('2026-04-03') = 'uk_goodfriday'
        and ripples.att_holiday('2026-07-03') = 'us_july4' and ripples.att_holiday('2026-09-25') = '' and ripples.att_easter(2026) = '2026-04-05';
  res := ripples._att_t(res, 'T1 holidays', ok, jsonb_build_object('thx', ripples.att_holiday('2025-11-27'), 'easter26', ripples.att_easter(2026)));

  -- T2 window statistic and CAR scaling on a deterministic array (N = 420, spike +5 then +4 at index 300/301)
  select array_agg((case when g = 300 then 5.0 when g = 301 then 4.0 else 0.0 end)::real order by g) into arr from generate_series(1, 420) g;
  s := ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', 1, 0, '2026-12-31', false);
  s2 := ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'car', 1, 0.5, '2026-12-31', false);
  ok := (s ->> 'S')::float8 = 5 and (s ->> 'lag')::int = 2 and abs((s2 ->> 'S')::float8 - 9.0 / (sqrt(8) * sqrt(3))) < 1e-9
        and (ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', -1, 0, '2026-12-31', false) ->> 'S')::float8 = 0
        and (ripples.att_win_stat(arr, null, '2025-01-01', 420, '2025-01-01'::date + 297, 7, 'peak', 0, 0, '2026-12-31', false) ->> 'S')::float8 = 5;
  res := ripples._att_t(res, 'T2 window statistic: peak, signed/unsigned, CAR = Σ/(√n·√((1+ρ)/(1−ρ)))', ok, jsonb_build_object('peak', s, 'car', s2));
  ok := abs(ripples.att_rho1(arr, '2025-01-01', 420, '2025-01-01'::date + 297)) < 1e-9;
  res := ripples._att_t(res, 'T2 rho1 of a flat baseline is 0', ok, null);

  -- T3 sd_null on iid uniform(−1.7, 1.7): CAR sd ≈ 0.98, peak(8) mean ≈ 1.48
  perform setseed(0.42);
  select array_agg(((random() * 2 - 1) * 1.7)::real order by g) into arr from generate_series(1, 420) g;
  s := ripples.att_sd_null_calc(arr, '2025-01-01', 420, 7, 'car', 1);
  s2 := ripples.att_sd_null_calc(arr, '2025-01-01', 420, 7, 'peak', 1);
  ok := abs((s ->> 'sd')::float8 - 0.98) < 0.15 and (s2 ->> 'mean')::float8 between 1.2 and 1.8 and (s ->> 'n')::int >= 250;
  res := ripples._att_t(res, 'T3 sd_null: CAR ≈ 1 on iid noise, peak null mean ≈ 1.5 (centred ž needed)', ok, jsonb_build_object('car', s, 'peak', s2));

  -- T4 pure weighted BH: p = {0.001, 0.01, 0.02, 0.5}, w = 1 → q = {0.004, 0.02, 0.02667, 0.5}; weights change the order
  q := ripples.att_bh_q(array[0.001, 0.01, 0.02, 0.5], array[1, 1, 1, 1]);
  ok := abs(q[1] - 0.004) < 1e-9 and abs(q[2] - 0.02) < 1e-9 and abs(q[3] - 0.0266667) < 1e-6 and abs(q[4] - 0.5) < 1e-9;
  s := to_jsonb(q);
  q := ripples.att_bh_q(array[0.02, 0.01], array[5, 0.2]);
  ok := ok and q[1] < q[2] and abs(q[1] - 2 * 0.02 / 5 / 1) < 1e-9;
  res := ripples._att_t(res, 'T4 weighted BH step-up (pure)', ok, jsonb_build_object('q_unweighted', s, 'q_weighted', to_jsonb(q)));

  -- T13 (B2) null scale: (a) iid noise → CAR sd floored at 1.0, peak floored at 0.5 when quieter; (b) a dormant series (zeros + 3 spikes) is
  -- degenerate (excluded); (c) a quiet series with a huge later regime: the null keyed on an onset inside the quiet part never sees the regime
  perform setseed(0.42);
  select array_agg(((random() * 2 - 1) * 0.6)::real order by g) into arr from generate_series(1, 1200) g;
  j := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1);
  select array_agg((case when g in (300, 700, 1100) then 12.0 else 0.0 end)::real order by g) into arr from generate_series(1, 1200) g;
  j2 := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 2, 'peak', 1);
  perform setseed(0.11);
  select array_agg((case when g <= 600 then (random() * 2 - 1) * 1.7 else (random() * 2 - 1) * 40 end)::real order by g) into arr from generate_series(1, 1200) g;
  j3 := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1, '2022-01-01'::date + 560, false);
  s := ripples.att_sd_null_calc(arr, '2022-01-01', 1200, 7, 'car', 1);
  ok := (j ->> 'sd')::float8 = 1.0 and (j ->> 'floored')::boolean
        and (j2 ->> 'sd') is null and j2 ->> 'reason' = 'degenerate'
        and (j3 ->> 'sd')::float8 < 1.5 and (s ->> 'sd')::float8 > 2.5 * (j3 ->> 'sd')::float8 and (j3 ->> 'to')::date <= '2022-01-01'::date + 560 - 7 - 30 - 7;
  res := ripples._att_t(res, 'T13 null scale: robust MAD with floors, degenerate series excluded, pre-onset windows only', ok, jsonb_build_object('iid', j, 'dormant', j2, 'pre_onset', j3 - 'from', 'whole_array', s - 'from' - 'to'));

  -- T14 (B4) holidays are common-shock days: Thanksgiving ± 1, Black Friday, Christmas week, July 4 observed
  ok := (select count(*) from ripples.att_common_days where day in ('2025-11-26', '2025-11-27', '2025-11-28', '2025-12-26', '2026-07-03', '2024-11-28')) = 6
        and not exists (select 1 from ripples.att_common_days where day = '2025-11-19');   -- an ordinary Wednesday (no holiday within a day) is not flagged
  res := ripples._att_t(res, 'T14 US federal holidays ± 1 d, Black Friday and Christmas week are registered common-shock days', ok,
           (select jsonb_agg(jsonb_build_object('day', day, 'reason', reason) order by day) from ripples.att_common_days where day between '2025-11-25' and '2025-11-29'));

  -- T15 (B4) geo_filter: an NYC transit item is proposed for a New York event, not for a Florida one, and not for an event without state meta
  insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
  values (null, 'test:geo:ny', 'test NY event', 'en', 'panel', false, 'cascade', '{"state": ["NY", "NJ"], "family": "hazard.storm"}'::jsonb),
         (null, 'test:geo:fl', 'test FL event', 'en', 'panel', false, 'cascade', '{"state": ["FL"], "family": "hazard.storm"}'::jsonb),
         (null, 'test:geo:none', 'test no-geo event', 'en', 'panel', false, 'cascade', '{"family": "hazard.storm"}'::jsonb);
  ok := (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:ny'))) = 1
        and (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:fl'))) = 0
        and (select count(*) from ripples.att_resolve_targets('{"node":"mta.ridership:subway","geo_filter":["US-NY","US-NJ","US-CT"],"sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:none'))) = 0
        and (select count(*) from ripples.att_resolve_targets('{"node":"tsa.pax:checkpoint","sign":-1}'::jsonb, (select topic_id from ripples.att_topics where label_key = 'test:geo:fl'))) = 1;
  res := ripples._att_t(res, 'T15 geo_filter honoured in target resolution (state ∩ filter; no state meta → not proposed)', ok, null);
  delete from ripples.att_topics where label_key like 'test:geo:%';

  -- T16 (S5) look schedule follows the frozen per-channel L: a template L = 7 on INST gives one look at +8; L = 90 gives +31/+61/+91
  ok := ripples.att_look_dates('INST', '2025-11-26', 7) = array['2025-12-04'::date] and ripples.att_look_dates('INST', '2025-11-26', 90) = array['2025-12-27'::date, '2026-01-26', '2026-02-25']
        and ripples.att_hop_l('INST', 'storm_nws_warnings') = 7 and ripples.att_hop_l('INST', 'storm_fema_decl') = 90 and ripples.att_hop_l('PHYS', null) = 7;
  res := ripples._att_t(res, 'T16 template L honoured per channel at freeze (INST 7 → one look at +8; INST 90 → +31/+61/+91)', ok, null);

  -- T5 every ledger freeze batch (not superseded) recomputes bit-identically and its frozen weights sum to its m (batches re-frozen by
  -- att_refreeze keep their original weights and are exempt from the weight sum)
  ok := (ripples.att_ledger_verify() ->> 'ok')::boolean;   -- chain + every registered verifier (covers non-candidate 'freeze' objects such as the 6.2 fx grid)
  for h in select l.seq, l.payload_hash fh, (l.ref ->> 'as_of')::date as_of, (l.ref ? 'refreeze_of') refrozen from ripples.att_ledger l
           where l.kind = 'freeze' and not (l.ref ? 'superseded_by') and l.ref ? 'as_of' and not (l.ref ? 'object') loop
    v_recomp := ripples.att_freeze_hash(h.as_of, false, h.fh);
    ok := ok and v_recomp = h.fh
          and (h.refrozen or abs((select sum(bh_weight) - count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)) < 1e-2 * greatest(1, (select count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)));
  end loop;
  res := ripples._att_t(res, 'T5 every frozen batch recomputes bit-identically and its BH weights sum to m', ok,
           jsonb_build_object('ledger_verify', ripples.att_ledger_verify(),
                              'other_freeze_objects', (select coalesce(jsonb_agg(jsonb_build_object('seq', seq, 'object', ref ->> 'object', 'method', ref ->> 'method')), '[]'::jsonb) from ripples.att_ledger where kind = 'freeze' and ref ? 'object'),
                              'batches', (select jsonb_agg(jsonb_build_object('as_of', x.as_of, 'batches', x.b, 'm', x.m)) from (select as_of, count(distinct frozen_hash) b, count(*) m from ripples.att_hop_candidates where frozen_hash is not null group by as_of) x)));
  ok := not exists (select 1 from ripples.att_hop_tests t where not exists (select 1 from ripples.att_hop_candidates c where c.hop_id = t.hop_id and c.frozen_hash is not null));
  res := ripples._att_t(res, 'T5 no att_hop_tests row without a frozen candidate', ok, null);

  -- T6 MONEY produces zero tests; IO edges produce zero tests; attention-only hops are never Measured
  ok := not exists (select 1 from ripples.att_hop_candidates c join ripples.att_node_series ns on ns.node = c.node where ns.channel = 'MONEY')
        and not exists (select 1 from ripples.att_hop_candidates c, jsonb_array_elements(c.path) p where p ->> 'type' = 'IO')
        and not exists (select 1 from ripples.att_hop_tests where tier = 'measured' and attention_only);
  res := ripples._att_t(res, 'T6 MONEY zero tests, IO zero tests, attention-only never Measured', ok, null);

  -- T7–T12 run on a synthetic fixture inside a sub-transaction that is rolled back at the end (p_cleanup = true): no fixture rows,
  -- ledger entries or freeze batches persist, so the live ledger stays bit-identical. The results (res) survive the rollback.
  begin
  -- T7 synthetic fixture: source test.synth (PHYS, level), 70 null series + 10 with an injected +0.3 log-unit response for 7 days after t0,
  -- 1,200 days of history (long-array path, daily date draws); iid log-noise, no weekly pattern (a weekly pattern with a plain baseline
  -- puts most placebo windows behind the pre-trend gate); targets: 10 null (s01–s10) + 10 injected (s71–s80); the 60 untargeted nulls form the topic pool
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
    select v_sid, d::date,
           exp(5 + 0.05 * (random() * 2 - 1) * 1.7
               + case when i > 70 and d::date between t0 and t0 + 6 then 0.30 else 0 end)
    from generate_series(current_date - 1200, current_date - 1, interval '1 day') d;
  end loop;
  perform ripples.att_build_zvec(current_date - 1, array['test.synth']);
  v_ev := ripples.att_library_event(null, 'Synthetic shock', 'test.synth', t0, 'library');
  run := ripples.att_run_library(v_ev);
  select count(*) filter (where hl.tier = 'measured' and hl.node >= 'test.synth:s71'), count(*) filter (where hl.tier in ('likely','measured') and hl.node <= 'test.synth:s10')
    into n_inj_meas, n_null_likely from ripples.att_hop_latest hl where hl.event_id = v_ev;
  select count(*), count(*) filter (where hl.tier = 'measured') into n_decoy_tested, n_decoy_meas
    from ripples.att_hop_latest hl join ripples.att_events e on e.event_id = hl.event_id where e.matched_to = v_ev and e.role = 'decoy' and hl.t_stat is not null;
  ok := n_inj_meas >= 8 and n_null_likely <= 1 and n_decoy_meas <= greatest(1, n_decoy_tested / 10);
  res := ripples._att_t(res, 'T7 synthetic fixture: injected targets Measured (recall ≥ 8/10), null targets flat, decoy Measured rate ≤ 0.10', ok,
           jsonb_build_object('injected_measured', n_inj_meas, 'null_likely_or_better', n_null_likely, 'decoy_tested', n_decoy_tested, 'decoy_measured', n_decoy_meas, 'run', run,
                              'nodes', (select jsonb_agg(jsonb_build_object('node', hl.node, 'tier', hl.tier, 'T', round(hl.t_stat::numeric, 2), 'p', hl.fluke, 'p_date', hl.p_date, 'n_date', hl.n_date, 'q', round(hl.q_w::numeric, 4), 'fails', hl.detail -> 'fails') order by hl.node)
                                        from ripples.att_hop_latest hl where hl.event_id = v_ev)));
  -- null uniformity: held-out p-values for the 50 null series at t0 (they carry no injected response)
  for i in 1..50 loop
    select series_id into v_sid from ripples.att_series where source = 'test.synth' and key = 's' || lpad(i::text, 2, '0');
    j := ripples.att_heldout_p(v_sid, t0, t0 + 7, 200);
    if (j ->> 'p') is not null then ps := ps || (j ->> 'p')::float8; end if;
  end loop;
  ks := ripples.att_ks_uniform(ps);
  ok := (ks ->> 'p')::float8 >= 0.05 and (select min(x) from unnest(ps) x) >= 1::float8 / 201 - 1e-12;
  res := ripples._att_t(res, 'T7 null p-values uniform (KS p ≥ 0.05) and floored at 1/(N+1)', ok, ks - 'hist' || jsonb_build_object('min_p', (select min(x) from unnest(ps) x)));
  -- placebo shift 0 identity: the 'rival' code path at the hop's own onset gives the same T as the real path
  select hl.hop_id, hl.look_no into v_hop, v_look from ripples.att_hop_latest hl where hl.event_id = v_ev and hl.t_stat is not null order by hl.t_stat desc limit 1;
  a := ripples.att_test_hop(v_hop, v_look, null, null);
  b := ripples.att_test_hop(v_hop, v_look, 'rival', v_ev::int);
  ok := abs((a ->> 'T')::float8 - (b ->> 'T')::float8) < 1e-9;
  res := ripples._att_t(res, 'T8 placebo draw at shift 0 equals the real statistic (identical code path)', ok, jsonb_build_object('T_real', a ->> 'T', 'T_shift0', b ->> 'T'));

  -- T9 (engine 6.1, B5) retraction of a SETTLED hop: publish the top hop, register its onset as a common-shock day, then run the nightly
  -- re-examination. The settled look keeps its q_w (nothing is nulled or rewritten); att_reexamine writes a new look row (look_no ≥ 100)
  -- through att_engine_job and att_finalize's retraction branch, appends the ledger row, and the retraction propagates to a child hop.
  insert into ripples.att_hop_registry(hop_id, window_close, p_hat, family, path_type, channel) select v_hop, window_close, 0.2, 'test.synth', path_type, 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop
  on conflict (hop_id) do nothing;
  update ripples.att_hop_registry set published_tier = 'measured', published_at = now() where hop_id = v_hop;
  v_q_before := (select q_w from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look);
  -- a depth-2 child of the published hop, Likely at its final look (its batch is synthetic: no ledger freeze row, never a calibration input)
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
  fin := ripples.att_reexamine(current_date, true, 600);
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

  -- T10 ledger chaining and a tamper check inside a savepoint
  lv := ripples.att_ledger_verify();
  ledger_ok := (lv ->> 'ok')::boolean;
  begin
    update ripples.att_ledger set payload_hash = repeat('0', 64) where seq = (select min(seq) from ripples.att_ledger where kind = 'freeze');
    tamper := ripples.att_ledger_verify();
    raise exception 'rollback tamper';
  exception when others then null; end;
  ok := ledger_ok and not (tamper ->> 'ok')::boolean and jsonb_array_length(tamper -> 'bad') >= 1;
  res := ripples._att_t(res, 'T10 ledger chain verifies; a tampered freeze row is detected', ok, jsonb_build_object('verify', lv - 'bad', 'tamper_bad', tamper -> 'bad'));

  -- T11 every test row carries its p floor and p_h ≥ floor; Measured rows carry an outcome channel
  ok := not exists (select 1 from ripples.att_hop_tests where fluke is not null and p_floor is not null and fluke < p_floor - 1e-9)
        and not exists (select 1 from ripples.att_hop_tests where tier = 'measured' and coalesce((detail ->> 'n_out3')::int, 0) < 1);
  res := ripples._att_t(res, 'T11 p-value floors respected; every Measured row has an outcome channel', ok, null);

  -- T12 no cascade payload carries a chain probability (Π(1−f) is internal to att_expand) or a "caused/drove/because of" claim
  select coalesce(jsonb_agg(distinct pk), '[]'::jsonb) into bad_keys
    from ripples.att_cascades c, jsonb_path_query(c.payload, 'strict $.**') p, jsonb_object_keys(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) pk
   where pk ~* 'chain_?(prob|f|cred)|compound|prob_true';
  ok := jsonb_array_length(bad_keys) = 0
        and not exists (select 1 from ripples.att_cascades c where c.payload::text ~* '\m(caused|drove|because of)\M');
  res := ripples._att_t(res, 'T12 no payload contains a chain probability or a causal claim', ok, jsonb_build_object('bad_keys', bad_keys));

  -- T17 (6.1) the fixture's frozen batch carries the frozen per-channel L, the engine and graph versions, has no duplicate (event, parent, node,
  -- sign) candidates (S3), and every finalised look was BH-scored on p_h (S1)
  ok := not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'library' and (c.l_by_channel is null or c.engine_version not like '6.1%' or c.graph_version is null))
        and (select l_by_channel ->> 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop) = '7'
        and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role <> 'negative_control' group by c.as_of, c.event_id, c.parent_hop, c.node, c.sign having count(*) > 1)
        and not exists (select 1 from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id where c.event_id = v_ev and t.q_w is not null and t.look_no < 100
                        and abs((t.detail -> 'bh' ->> 'p_bh')::float8 - ripples.att_bh_input(t.p_date, t.n_date, t.p_topic, t.n_topic, t.p_link, t.n_link, t.fluke, coalesce((ripples._att_cfg('engine') ->> 'bh_min_draws')::int, 200))::float8) > 1e-6)
        and (select every(sign <> 0) from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'negative_control');
  res := ripples._att_t(res, 'T17 frozen L / versions on the batch, no duplicate paths, BH input = max over families with >= bh_min_draws draws (p_h fallback), signed negative controls', ok,
           (select jsonb_build_object('l_by_channel', l_by_channel, 'engine_version', engine_version, 'graph_version', left(graph_version, 12)) from ripples.att_hop_candidates where hop_id = v_hop));

  -- T18 (B4, the audit's stop case) a storm with onset in Thanksgiving week 2025 over New York proposes the NYC transit targets (geo filter)
  -- and can NEVER reach Measured: the onset and the window's peak sit on registered common-shock days. Real data, real code path.
  if p_only is null or 'T18' = any(p_only) then
  v_ev2 := ripples.att_library_event(null, 'Test Thanksgiving-week storm (NY)', 'hazard.storm', '2025-11-26', 'library',
                                     '{"state": ["NY", "NJ"], "ba": ["NYIS"]}'::jsonb);
  run2 := ripples.att_run_library(v_ev2);
  select count(*) filter (where hl.tier = 'measured'), count(*) filter (where hl.t_stat is not null) into n_meas2, n_tested2
    from ripples.att_hop_latest hl join ripples.att_events e on e.event_id = hl.event_id where e.event_id = v_ev2 or e.matched_to = v_ev2;
  select hl.node, hl.tier, hl.tier_reason, hl.flags, hl.t_stat, hl.common_shock into v_sub
    from ripples.att_hop_latest hl where hl.event_id = v_ev2 and hl.node = 'mta.ridership:subway' order by hl.look_no desc limit 1;
  ok := n_meas2 = 0 and n_tested2 > 0
        and exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev2 and c.node = 'mta.ridership:subway')
        and coalesce(v_sub.tier, 'watching') <> 'measured'
        and (v_sub.t_stat is null or coalesce(v_sub.common_shock, false))
        and (select count(*) from ripples.att_common_days where day between '2025-11-26' and '2025-11-28') = 3;
  res := ripples._att_t(res, 'T18 Thanksgiving-week storm over New York: NYC transit proposed, common-shock flagged, never Measured (real data)', ok,
           jsonb_build_object('measured', n_meas2, 'tested', n_tested2, 'subway', to_jsonb(v_sub), 'run', run2 - 'freeze' - 'depth2',
                              'nodes', (select jsonb_agg(jsonb_build_object('node', hl.node, 'tier', hl.tier, 'T', round(hl.t_stat::numeric, 2), 'flags', hl.flags) order by hl.node) from ripples.att_hop_latest hl where hl.event_id = v_ev2)));
  end if;

    if p_cleanup then raise exception using errcode = 'P0999', message = 'fixture rollback'; end if;
  exception when sqlstate 'P0999' then null;
  end;
  return jsonb_build_object('ok', not exists (select 1 from jsonb_array_elements(res) r where not (r ->> 'ok')::boolean), 'tests', res);
end $$;
revoke all on function ripples.att_test_engine(boolean, text[]) from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- On-demand runners. The harness takes ~8 minutes, longer than the 2-minute statement_timeout the MCP/pg_cron sessions
-- inherit, so it is run by a request flag polled by a short-lived pg_cron loop:
--   select ripples.att_state_set('engine.test.request', '{"status":"pending"}');
--   select cron.schedule('att-test-loop', '* * * * *', $$set statement_timeout = '90min'; select ripples.att_test_runner()$$);
-- The result lands in att_state 'engine.test' (tests[] + ok + seconds); unschedule the loop when done. Same shape for the
-- deploy gate (att_run_controls) via 'engine.controls.request' / 'engine.controls' / att-controls-loop. Neither loop is
-- part of the daily schedule; nothing here writes secrets or key names.
create or replace function ripples.att_test_runner() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare req jsonb := coalesce(ripples.att_state_get('engine.test.request'), '{}'::jsonb); r jsonb; ctx text; t0 timestamptz := clock_timestamp();
begin
  if coalesce(req ->> 'status', '') <> 'pending' then return jsonb_build_object('idle', true); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_test_runner')) then return jsonb_build_object('skipped', 'running'); end if;
  begin
    r := ripples.att_test_engine(true, case when req ? 'only' then (select array_agg(x) from jsonb_array_elements_text(req -> 'only') x) end);
    perform ripples.att_state_set('engine.test', r || jsonb_build_object('at', now(), 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
    perform ripples.att_state_set('engine.test.request', jsonb_build_object('status', 'done', 'at', now()));
  exception when others or query_canceled then
    get stacked diagnostics ctx = pg_exception_context;
    perform ripples.att_state_set('engine.test', jsonb_build_object('error', sqlerrm, 'state', sqlstate, 'ctx', left(ctx, 800), 'at', now(),
                                                                    'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
    perform ripples.att_state_set('engine.test.request', jsonb_build_object('status', 'failed', 'at', now()));
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_test_runner'));
  return coalesce(ripples.att_state_get('engine.test'), '{}'::jsonb) - 'tests';
end $$;
revoke all on function ripples.att_test_runner() from anon, authenticated, public;

create or replace function ripples.att_controls_runner() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare req jsonb := coalesce(ripples.att_state_get('engine.controls.request'), '{}'::jsonb); r jsonb; ctx text; t0 timestamptz := clock_timestamp();
begin
  if coalesce(req ->> 'status', '') <> 'pending' then return jsonb_build_object('idle', true); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_controls_runner')) then return jsonb_build_object('skipped', 'running'); end if;
  begin
    r := ripples.att_run_controls(false);
    perform ripples.att_state_set('engine.controls', r || jsonb_build_object('at', now(), 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
    perform ripples.att_state_set('engine.controls.request', jsonb_build_object('status', 'done', 'at', now()));
  exception when others or query_canceled then
    get stacked diagnostics ctx = pg_exception_context;
    perform ripples.att_state_set('engine.controls', jsonb_build_object('error', sqlerrm, 'state', sqlstate, 'ctx', left(ctx, 800), 'at', now()));
    perform ripples.att_state_set('engine.controls.request', jsonb_build_object('status', 'failed', 'at', now()));
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_controls_runner'));
  return coalesce(ripples.att_state_get('engine.controls'), '{}'::jsonb) - 'positive';
end $$;
revoke all on function ripples.att_controls_runner() from anon, authenticated, public;

-- =====================================================================================================================
-- Engine 6.2 (30_att_engine_62_pooled_regional.sql): T19–T25. Run: select ripples.att_test_engine_62();  (service_role)
-- Pure tests on synthetic panels (no writes outside a temp table) plus the hook-install invariants on the live att_finalize.
-- =====================================================================================================================
create or replace function ripples.att_test_engine_62() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare res jsonb := '[]'::jsonb; ok boolean; r float8[]; j jsonb; j0 jsonb; ps float8[]; pc int2[]; days date[]; regs text[]; nr int := 12; n int := 900;
        i int; k int; v float8; acc float8; row_ps float8[]; row_pc int2[]; cfg jsonb; def text; w float8[]; hk text[];
begin
  cfg := ripples._att_cfg('engine62') || '{"n_time": 24, "n_space": 20, "n_synth": 12}'::jsonb;
  -- T19 DerSimonian–Laird on known inputs: homogeneous → τ² = 0, I² = 0, pooled = precision-weighted mean; heterogeneous → τ² > 0
  r := ripples.att_fx_dl(array[0.10, 0.10, 0.10], array[0.05, 0.05, 0.05]);
  ok := abs(r[1] - 0.10) < 1e-9 and abs(r[2] - 0.05 / sqrt(3)) < 1e-9 and r[3] = 0 and r[4] = 0;
  r := ripples.att_fx_dl(array[0.5, -0.4, 0.6, -0.5], array[0.05, 0.05, 0.05, 0.05]);
  ok := ok and r[3] > 0.1 and r[4] > 0.9 and abs(r[1] - 0.05) < 0.01;
  res := ripples._att_t(res, 'T19 DL random effects (homogeneous / heterogeneous)', ok, jsonb_build_object('tau2', r[3], 'i2', r[4], 'pooled', r[1]));

  -- synthetic panel: 12 regions × 900 days, AR(1)-ish noise with a shared seasonal + a common shock; regions 1–2 get +0.30 from day 700 for 7 days
  perform setseed(0.42);
  select array_agg(d::date order by d) into days from generate_series('2020-01-01'::date, '2020-01-01'::date + (n - 1), '1 day') d;
  select array_agg('R' || lpad(x::text, 2, '0') order by x) into regs from generate_series(1, nr) x;
  ps := '{}'; pc := '{}';
  for k in 1..nr loop
    row_ps := array_fill(0::float8, array[n]); row_pc := array_fill(0::int2, array[n]); acc := 0; v := 0;
    for i in 1..n loop
      v := 0.6 * v + 0.05 * (random() - 0.5) * 2;                                             -- region noise
      acc := acc + 5 + 0.20 * sin(2 * pi() * i / 365.0) + v + case when i between 500 and 506 then 0.5 else 0 end   -- season + common shock at 500
             + case when k <= 2 and i between 700 and 706 then 0.30 else 0 end;
      row_ps[i] := acc; row_pc[i] := i;
    end loop;
    if k = 1 then ps := array[row_ps]; pc := array[row_pc]; else ps := ps || row_ps; pc := pc || row_pc; end if;
  end loop;
  -- T20 DiD recovers the injected effect at day 700 (treated R01,R02), common shock at day 500 cancels (|d| small)
  j := ripples.att_fx_calc(ps, pc, days, regs, 'day', array['R01', 'R02'], days[700], 28, 7, 0, true, 0.11, cfg);
  j0 := ripples.att_fx_calc(ps, pc, days, regs, 'day', array['R01', 'R02'], days[500], 28, 7, 0, true, 0.12, cfg);
  ok := abs((j ->> 'd')::float8 - 0.30) < 0.06 and (j ->> 'p_space')::float8 <= 0.10 and (j ->> 'z')::float8 > 3
        and abs((j0 ->> 'd')::float8) < 0.08 and (j0 ->> 'p_space')::float8 > 0.10;
  res := ripples._att_t(res, 'T20 DiD: injected +0.30 recovered, common shock cancels', ok,
           jsonb_build_object('d', j ->> 'd', 'z', j ->> 'z', 'p_space', j ->> 'p_space', 'p_pre', j ->> 'p_pre', 'shock_d', j0 ->> 'd', 'shock_p_space', j0 ->> 'p_space'));
  -- T21 pre-trends flat on the injected event, synthetic control agrees in sign with a large RMSPE ratio
  ok := (j ->> 'p_pre')::float8 >= 0.10 and (j ->> 'synth_d')::float8 > 0.15 and (j ->> 'synth_ratio')::float8 > 2 and (j ->> 'synth_p')::float8 <= 0.15;
  res := ripples._att_t(res, 'T21 pre-trend joint test flat; synthetic control recovers sign with RMSPE-ratio rank p', ok,
           jsonb_build_object('p_pre', j ->> 'p_pre', 'lead', j -> 'lead', 'synth_d', j ->> 'synth_d', 'synth_ratio', j ->> 'synth_ratio', 'synth_p', j ->> 'synth_p'));
  -- T22 a pre-trending treated unit is caught: add a ramp to R03 before day 800 and test R03 at day 800
  -- ps is a prefix sum: a daily ramp of +0.01/day from day 761 is the prefix 0.01·m(m+1)/2 with m = i − 760
  for i in 761..n loop ps[3][i] := ps[3][i] + 0.01 * (i - 760) * (i - 759) / 2.0; end loop;
  j0 := ripples.att_fx_calc(ps, pc, days, regs, 'day', array['R03'], days[800], 28, 7, 0, false, 0.13, cfg);
  ok := (j0 ->> 'p_pre')::float8 < 0.10;
  res := ripples._att_t(res, 'T22 pre-trending treated unit fails the flat-leads test', ok, jsonb_build_object('p_pre', j0 ->> 'p_pre', 'lead', j0 -> 'lead', 'd', j0 ->> 'd'));
  -- T23 Wilson interval and BH labelling helpers
  w := ripples.att_fx_wilson(0, 20);
  ok := w[1] = 0 and abs(w[2] - 0.161) < 0.01;
  w := ripples.att_fx_wilson(2, 40);
  ok := ok and abs(w[1] - 0.0138) < 0.005 and abs(w[2] - 0.162) < 0.01;
  ok := ok and ripples.att_fx_idx(days, days[10]) = 10 and ripples.att_fx_idx(days, days[10] - 1) = 9 and ripples.att_fx_idx(days, days[n] + 1) is null;
  res := ripples._att_t(res, 'T23 Wilson CI (0/20, 2/40) and obs-index search', ok, jsonb_build_object('w0', ripples.att_fx_wilson(0, 20), 'w2', ripples.att_fx_wilson(2, 40)));
  -- T24 hook invariants: installed exactly once in the LIVE att_finalize; idempotent; substantive failures are never liftable
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'att_finalize';
  ok := (length(def) - length(replace(def, 'ripples.att_fx_hook(r.hop_id, r.look_no, fails)', ''))) / length('ripples.att_fx_hook(r.hop_id, r.look_no, fails)') = 1
        and (ripples.att_fx_hook_install() ->> 'already')::boolean;
  hk := ripples.att_fx_hook(-1, 1, array['common shock day', 'already moving', 'q above 0.05']);
  ok := ok and hk = array['common shock day', 'already moving', 'q above 0.05'];
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'att_fx_hook';
  ok := ok and position('''common shock day''' in split_part(def, 'lifted := array(', 2)) = 0 and position('''already moving''' in split_part(def, 'lifted := array(', 2)) = 0
        and position('''reversed''' in split_part(def, 'lifted := array(', 2)) = 0;
  res := ripples._att_t(res, 'T24 6.2 hook installed once, idempotent, unknown hop is a no-op, common-shock / already-moving / reversed never lifted', ok, jsonb_build_object('hook_noop', hk));
  -- T25 the Thanksgiving-week storm (2025-11-26, New York) on the real grid panel: whatever the contrast says, the hook cannot clear
  -- 'common shock day' (registered holiday) — Measured stays unreachable by construction
  hk := ripples.att_fx_hook(-1, 1, array['common shock day']);
  ok := hk = array['common shock day'] and ripples.att_holiday('2025-11-27') = 'us_thanksgiving';
  res := ripples._att_t(res, 'T25 Thanksgiving-week storm: common-shock failure survives the 6.2 hook', ok, jsonb_build_object('fails', hk));
  return jsonb_build_object('ok', (select bool_and((x ->> 'ok')::boolean) from jsonb_array_elements(res) x), 'tests', res);
end $$;
revoke all on function ripples.att_test_engine_62() from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- Story layer (31_att_story_layer.sql): T30–T37. Run: select ripples.att_test_story();  (service_role; standalone, read-only)
-- Invariants: story fields never alter an evidence tier; no 'chain' edge without mediation support; Likely / Watching never carry Measured
-- wording; a gate-demoted hop is always shown demoted with the gate's reason; Non-Event (Ghost / Dead end) only for pre-registered expected
-- effects that stayed flat; coherence gates exclude regardless of score; the public RPC matches its fixture and leaks nothing.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_test_story() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare res jsonb := '[]'::jsonb; ok boolean; n_bad int; n_rows int; det jsonb; cfg jsonb := ripples._att_cfg('story'); s1 real; s2 real; s3 real; s4 real; j jsonb; t text;
        today date := (now() at time zone 'utc')::date; ct jsonb; cp jsonb;
begin
  -- T30 story fields never alter an evidence tier: (a) engine_tier equals the root's tier in the engine's published cascade payload, tier equals
  -- the pure gate mapping; (b) no story function writes to any engine table (static check on every att_story_* / rm_story_* body)
  select count(*), count(*) filter (where not okk) into n_rows, n_bad from (
    select s.story_id,
           s.engine_tier = (select n ->> 'tier' from ripples.att_cascades c, jsonb_array_elements(c.payload -> 'nodes') n where c.event_id = s.event_id and (n ->> 'hop_id')::bigint = s.root_hop)
           and s.tier = (ripples.att_story_public_tier(s.engine_tier, case when s.engine_tier = 'measured' then ripples.att_ce_gate(s.root_hop, 'measured') end) ->> 'tier') okk
      from ripples.att_story_candidates s where s.story_kind in ('cascade','watching')) x;
  select count(*) into n_bad from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'ripples' and (p.proname like 'att\_story\_%' or p.proname like 'rm\_story%' or p.proname like 'rm\_stories%')
     and lower(pg_get_functiondef(p.oid)) ~ '(update|insert into|delete from)\s+ripples\.(att_hop_tests|att_hop_candidates|att_cascades|att_cascade_versions|att_hop_registry|att_ledger|att_fx_pool|att_fx_event|rm_public_versions)\M';
  ok := n_bad = 0 and (n_rows = 0 or (select count(*) from ripples.att_story_candidates s where s.story_kind in ('cascade','watching')
          and not (s.engine_tier = (select n ->> 'tier' from ripples.att_cascades c, jsonb_array_elements(c.payload -> 'nodes') n where c.event_id = s.event_id and (n ->> 'hop_id')::bigint = s.root_hop))) = 0);
  res := ripples._att_t(res, 'T30 story fields never alter an evidence tier (engine payload = engine_tier; gate mapping = tier; no story function writes an engine table)', ok,
                        jsonb_build_object('rows', n_rows, 'writers', n_bad));
  -- T31 no 'chain' edge without mediation support: pure rule + every stored edge re-derived from the engine's chaining record
  ok := ripples.att_story_edge_kind(null, null) = 'fork'
        and ripples.att_story_edge_kind('{"fork_test": false, "mediation_c": true}', null) = 'chain'
        and ripples.att_story_edge_kind('{"fork_test": true, "mediation_c": true}', null) = 'fork'
        and ripples.att_story_edge_kind('{"fork_test": false}', null) = 'fork'
        and ripples.att_story_edge_kind('{"fork_test": false, "mediation_c": true}', to_jsonb(1201)) = 'fork';
  select count(*) into n_bad from ripples.att_story_candidates s, jsonb_array_elements(s.graph -> 'edges') e
   where e ->> 'kind' = 'chain'
     and ripples.att_story_edge_kind((select t.detail -> 'chain' from ripples.att_hop_tests t where t.hop_id = (e ->> 'to')::bigint and t.tier is not null order by t.look_no desc limit 1),
                                     (select n -> 'fork_of' from ripples.att_cascades c, jsonb_array_elements(c.payload -> 'nodes') n where c.event_id = s.event_id and (n ->> 'hop_id')::bigint = (e ->> 'to')::bigint)) <> 'chain';
  select count(*) into n_rows from ripples.att_story_candidates s, jsonb_array_elements(s.graph -> 'edges') e where e ->> 'kind' = 'chain';
  ok := ok and n_bad = 0 and not exists (select 1 from ripples.att_story_candidates s where (s.fields ->> 'mediation_supported')::boolean
                                          and exists (select 1 from jsonb_array_elements(s.graph -> 'edges') e where e ->> 'kind' <> 'chain' and e ->> 'from' <> 'event' and e ->> 'from' <> 'family'));
  res := ripples._att_t(res, 'T31 no chain edge without engine mediation support (pure rule; every stored chain edge re-derived)', ok, jsonb_build_object('chain_edges', n_rows, 'unsupported', n_bad));
  -- T32 Likely / Watching / dead-end stories never carry Measured wording; the copy verbs are tier-honest and never causal
  cp := ripples.att_story_copy('cascade', 'Blind Spot', 'likely', 'Event X', 'Storm', 'Stop Y', 'jobs', 3, '{"domains_crossed": 1, "days": 3, "depth": 1}', null, null, false, 'u');
  ok := ripples.att_story_tier_wording('likely') not like '%Measured%' and ripples.att_story_tier_wording('watching') not like '%Measured%'
        and ripples.att_story_tier_wording('flat', 'non_event') not like '%Measured%' and ripples.att_story_tier_wording('measured') like 'Measured movement%'
        and (cp ->> 'story_sentence') like '%may have shown up in%' and (cp ->> 'story_sentence') !~* '\m(caused|drove|because of)\M'
        and (ripples.att_story_copy('watching', null, 'watching', 'Event X', 'Storm', 'Stop Y', 'jobs', null, '{}', null, '{"days_to_resolve": 4, "expected_1_in": 5}', false, 'u') ->> 'story_sentence') like '%might be showing up in%'
        and (ripples.att_story_copy('non_event', 'Dead end', 'flat', 'Event X', 'Storm', 'Stop Y', 'jobs', null, '{}', null, '{"expected_1_in": 5}', false, 'u') ->> 'story_sentence') like '%window closed flat%'
        and (ripples.att_story_copy('cascade', null, 'measured', 'Event X', 'Storm', 'Stop Y', 'jobs', 3, '{"domains_crossed": 1, "days": 3, "depth": 1}', null, null, false, 'u') ->> 'story_sentence') like '% showed up in %';
  select count(*) into n_bad from ripples.att_story_candidates s
   where s.tier <> 'measured' and ((s.copy ->> 'story_sentence') like '% showed up in %' and (s.copy ->> 'story_sentence') not like '%may have shown up in%'
                                    or (s.copy ->> 'story_sentence') like '%Measured movement%' or (s.copy ->> 'share_line') like '%· Measured ·%'
                                    or (s.copy ->> 'story_sentence') ~* '\m(caused|drove|because of|flooded into)\M');
  ok := ok and n_bad = 0;
  res := ripples._att_t(res, 'T32 Likely / Watching / dead-end stories never carry Measured wording; verbs tier-honest, never causal', ok, jsonb_build_object('bad_rows', n_bad, 'sample', cp ->> 'story_sentence'));
  -- T33 a forecast-gate demotion is always shown at the demoted tier with the gate's reason (pure mapping + every stored row + the public list)
  j := ripples.att_story_public_tier('measured', '{"tier": "likely", "reason": "forecast check pending", "engine_tier": "measured"}');
  ok := j ->> 'tier' = 'likely' and (j ->> 'demoted')::boolean and j ->> 'reason' = 'forecast check pending'
        and (ripples.att_story_public_tier('measured', '{"tier": "measured"}') ->> 'demoted')::boolean = false
        and ripples.att_story_public_tier('likely', null) ->> 'tier' = 'likely' and ripples.att_story_public_tier('measured', null) ->> 'tier' = 'measured';
  select count(*) into n_bad from ripples.att_story_candidates s where (s.gate ->> 'demoted')::boolean and (s.tier = 'measured' or s.gate ->> 'reason' is null);
  ok := ok and n_bad = 0 and not exists (select 1 from jsonb_array_elements(public.rm_stories(50, 36500, null) -> 'featured') f
                                          where (f ->> 'engine_tier') = 'measured' and (f ->> 'tier') <> 'measured' and (f ->> 'gate_reason') is null);
  res := ripples._att_t(res, 'T33 gate demotion always shown demoted with the gate reason (mapping, table, public list)', ok, jsonb_build_object('bad_rows', n_bad, 'mapping', j));
  -- T34 Non-Event (Ghost / Dead end) only for pre-registered expected effects (p_hat > 0) whose window closed with a flat final verdict
  select count(*) into n_rows from ripples.att_story_candidates where story_kind = 'non_event';
  select count(*) into n_bad from ripples.att_story_candidates s, unnest(s.hop_ids) h
   where s.story_kind = 'non_event'
     and not exists (select 1 from ripples.att_hop_registry r join ripples.att_hop_candidates c on c.hop_id = r.hop_id
                      where r.hop_id = h and r.p_hat > 0 and c.window_close < today
                        and (select t.tier from ripples.att_hop_tests t where t.hop_id = h and t.tier is not null order by t.look_no desc limit 1) = 'flat');
  ok := n_bad = 0 and not exists (select 1 from ripples.att_story_candidates where story_kind = 'non_event' and (tier <> 'flat' or archetype not in ('Ghost', 'Dead end')))
        and (ripples.att_story_archetypes('non_event', '{}'))[1] = 'Dead end' and (ripples.att_story_archetypes('ghost', '{}'))[1] = 'Ghost'
        and ripples.att_story_archetypes('cascade', '{"evidence_at_transitions": 0.6}') is distinct from array['Dead end'];
  res := ripples._att_t(res, 'T34 Non-Event stories only for pre-registered expected effects that stayed flat', ok, jsonb_build_object('non_events', n_rows, 'bad', n_bad));
  -- T35 coherence gates exclude regardless of score; the score is pure, bounded, order-only and favours counterintuitive findings (D-16)
  s1 := ripples.att_story_score('{"temporal_coherence": 1, "mechanism_coherence": 1, "evidence_at_transitions": 0.6, "surprise": 0.2, "counterintuitiveness": 0.2, "magnitude": 0.5}', cfg);
  s2 := ripples.att_story_score('{"temporal_coherence": 1, "mechanism_coherence": 1, "evidence_at_transitions": 0.6, "surprise": 0.8, "counterintuitiveness": 0.9, "magnitude": 0.5}', cfg);
  s3 := ripples.att_story_score('{"temporal_coherence": 1, "mechanism_coherence": 1, "evidence_at_transitions": 1, "surprise": 1, "counterintuitiveness": 1, "magnitude": 1, "replication": 1, "domain_diversity": 1, "independent_confirmations": 1, "visual_clarity": 1, "novelty": 1}', cfg);
  s4 := ripples.att_story_score('{"temporal_coherence": 0, "mechanism_coherence": 0, "common_cause_risk": 1, "length": 4, "branching_noise": 1}', cfg);
  ok := s2 > s1 and s3 <= 1 and s4 >= 0 and s3 > s2
        and ripples.att_story_gate('{"temporal_coherence": 0.4, "mechanism_coherence": 1, "labels_ok": true}', cfg) = 'low temporal coherence'
        and ripples.att_story_gate('{"temporal_coherence": 1, "mechanism_coherence": 0.3, "labels_ok": true}', cfg) like 'no mechanism%'
        and ripples.att_story_gate('{"temporal_coherence": 1, "mechanism_coherence": 1, "labels_ok": false}', cfg) = 'waiting for a public name'
        and ripples.att_story_gate('{"temporal_coherence": 1, "mechanism_coherence": 1, "labels_ok": true}', cfg) is null
        and not exists (select 1 from ripples.att_story_candidates s where s.featurable and ((s.fields ->> 'temporal_coherence')::float8 < (cfg -> 'gates' ->> 'temporal_min')::float8
                                                                                        or (s.fields ->> 'mechanism_coherence')::float8 < (cfg -> 'gates' ->> 'mechanism_min')::float8
                                                                                        or not (s.fields ->> 'labels_ok')::boolean));
  res := ripples._att_t(res, 'T35 coherence gates exclude regardless of score; score pure, bounded, counterintuitive favoured', ok, jsonb_build_object('unsurprising', s1, 'surprising', s2, 'max', s3, 'min', s4));
  -- T36 the archetype rules are deterministic on fields (one example each of the merged D-14/D-15/D-16 list)
  ok := (ripples.att_story_archetypes('cascade', '{"length": 2, "mediation_supported": true, "domain_diversity": 2, "surprise": 0.7, "evidence_at_transitions": 1}'))[1] = 'Detour'
        and (ripples.att_story_archetypes('cascade', '{"event_domains_likely": 3}'))[1] = 'Branch'
        and (ripples.att_story_archetypes('cascade', '{"event_domains_likely": 2}'))[1] = 'Echo'
        and (ripples.att_story_archetypes('cascade', '{"funnel_siblings": 3}'))[1] = 'Funnel'
        and (ripples.att_story_archetypes('cascade', '{"direction_unexpected": true}'))[1] = 'Bounce'
        and (ripples.att_story_archetypes('cascade', '{"magnitude": 0.9, "shock": 0.2}'))[1] = 'Amplifier'
        and (ripples.att_story_archetypes('cascade', '{"evidence_at_transitions": 0.6, "surprise": 0.7}'))[1] = 'Blind Spot'
        and (ripples.att_story_archetypes('cascade', '{"evidence_at_transitions": 0.6, "hero_lag_days": 9}'))[1] = 'Delay'
        and (ripples.att_story_archetypes('cascade', '{"shared_stop": true, "event_domains_likely": 3}'))[1] = 'Shared Stop'
        and ripples.att_story_archetypes('watching', '{"evidence_at_transitions": 0.2, "surprise": 0.9}') = '{}'
        and ripples.att_story_archetypes('cascade', '{"length": 2, "mediation_supported": false, "domain_diversity": 2, "surprise": 0.7}') is distinct from array['Detour'];
  res := ripples._att_t(res, 'T36 archetype rules deterministic (Detour needs mediation; Watching has none)', ok, null);
  -- T37 public contract: fixture shape, leak guard, no causal words, RLS on both tables, no anon grant on any story function, controls never featured
  ct := ripples.rm_story_contract_test();
  ok := (ct ->> 'ok')::boolean
        and (select bool_and(c.relrowsecurity) from pg_class c join pg_namespace ns on ns.oid = c.relnamespace where ns.nspname = 'ripples' and c.relname in ('att_story_candidates', 'att_story_featured'))
        and not exists (select 1 from ripples.rm_grant_audit() g where g.fn like '%story%')
        and not exists (select 1 from jsonb_array_elements(public.rm_stories(50, 36500, null) -> 'featured') f where (f ->> 'is_control')::boolean);
  res := ripples._att_t(res, 'T37 public rm_stories matches stories.json, leaks nothing, RLS on, no anon grants, controls never featured', ok,
                        jsonb_build_object('diffs', ct -> 'diffs', 'leaks', ct -> 'leaks', 'coverage', ct -> 'coverage', 'causal_words', ct -> 'causal_words'));
  return jsonb_build_object('ok', (select bool_and((x ->> 'ok')::boolean) from jsonb_array_elements(res) x), 'tests', res);
end $$;
revoke all on function ripples.att_test_story() from anon, authenticated, public;
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

-- =====================================================================================================================
-- ENGINE 6.3 tests T40–T49 (32_att_engine_63_discovery.sql). Run: select ripples.att_test_engine_63();  (service_role)
-- T40 split integrity (disjoint halves, frozen held-out lists, ledger snapshot) · T41 selection rule deterministic / pure ·
-- T42 confirmation BH over the confirmation set only, confirmed ⇒ sign agrees · T43 6.3 never touches 6.1/6.2 tiering ·
-- T44 spike-in power: delayed window catches a delayed effect; daily vs weekly-sum on sparse counts (ratio reported, no gain on iid counts) · T45 EB shrinkage ·
-- T46 decoy calibration on the ledger · T47 surprise fields · T48 Thanksgiving / tier guard (no tier words anywhere in 6.3 output) ·
-- T49 ledger rows + att_ledger_verify.
-- =====================================================================================================================
create or replace function ripples._att_t63_prefix(p_vals float8[][]) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare nr int := array_length(p_vals, 1); n int := array_length(p_vals, 2); ps float8[] := '{}'; pc int2[] := '{}'; r int; i int; acc float8; cnt int; ps_r float8[]; pc_r int2[];
begin
  for r in 1..nr loop
    acc := 0; cnt := 0; ps_r := array_fill(0::float8, array[n]); pc_r := array_fill(0::int2, array[n]);
    for i in 1..n loop if p_vals[r][i] is not null then acc := acc + p_vals[r][i]; cnt := cnt + 1; end if; ps_r[i] := acc; pc_r[i] := cnt; end loop;
    if cardinality(ps) = 0 then ps := array[ps_r]; pc := array[pc_r]; else ps := ps || ps_r; pc := pc || pc_r; end if;
  end loop;
  return jsonb_build_object('ps', to_jsonb(ps), 'pc', to_jsonb(pc));
end $$;

create or replace function ripples.att_test_engine_63(p_batch text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare res jsonb := '[]'::jsonb; ok boolean; j jsonb; b record; n_bad int; n_rows int; cfg jsonb := ripples._att_cfg('engine63'); rule jsonb; k_cap int;
        sel_before int[]; sel_after int[]; ids int[]; ps float8[]; qs float8[]; i int; cal jsonb; lv jsonb;
        vals float8[][]; ps_a float8[]; pc_a int2[]; regs text[]; days date[]; x_imm float8[]; x_del float8[]; jd jsonb;
        wvals float8[][]; wdays date[]; jw jsonb; z_day float8; z_week float8; nr int := 12; nd int := 900; r int; t int; v float8; lam float8;
        sh record; n_sh int := 0; pool float8; txt text; hk text;
begin
  select * into b from ripples.att_fx63_batch where (p_batch is null or batch = p_batch) order by created_at desc limit 1;
  rule := cfg -> 'rule'; k_cap := (rule ->> 'k_cap')::int;
  -- T40 split integrity
  select count(*) into n_bad from ripples.att_fx_event x join ripples.att_fx_event c on c.grid_id = x.grid_id and c.event_id = x.event_id and c.role = 'confirm'
   join ripples.att_fx_grid g on g.grid_id = x.grid_id where x.role = 'explore' and g.batch like b.batch || '/%';
  ok := b.batch is not null and n_bad = 0
        and (select coalesce(max(f.onset) < b.split_date, true) from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like b.batch || '/%' and f.role = 'explore')
        and (select coalesce(min(f.onset) >= b.split_date, true) from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like b.batch || '/%' and f.role = 'confirm')
        and not exists (select 1 from ripples.att_fx63_select s where s.batch = b.batch and s.decoy_set = 0 and s.selected
                         and ripples.att_fx63_confirm_hash(s.grid_id) is distinct from (b.confirm_hashes ->> s.grid_id::text))
        and exists (select 1 from ripples.att_ledger l join ripples.att_freeze_snapshots sn on sn.seq = l.seq where l.seq = b.explore_seq and l.kind = 'freeze' and l.payload_hash = b.explore_hash
                     and sn.payload -> 'confirm_hashes' = b.confirm_hashes);
  res := ripples._att_t(res, 'T40 split integrity: explore < split ≤ confirm, no event in both halves, held-out lists match the exploration-freeze hashes and the ledger snapshot', ok,
                        jsonb_build_object('batch', b.batch, 'split', b.split_date, 'overlap_rows', n_bad, 'explore_seq', b.explore_seq, 'confirm_seq', b.confirm_seq));
  -- T41 selection rule: idempotent re-run inside a savepoint gives the same selected set; every selected row obeys the rule
  select array_agg(grid_id order by grid_id) into sel_before from ripples.att_fx63_select where batch = b.batch and decoy_set = 0 and selected;
  begin
    perform ripples.att_fx63_select_run(b.batch, 0);
    select array_agg(grid_id order by grid_id) into sel_after from ripples.att_fx63_select where batch = b.batch and decoy_set = 0 and selected;
    raise exception 'rollback' using errcode = 'P0001';
  exception when others then null; end;
  select count(*) into n_bad from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = b.batch and s.decoy_set = 0 and s.selected and (not s.x_ok or s.x_p > (rule ->> 'x_p_max')::float8 or s.x_n < (rule ->> 'x_n_min')::int or (g.bh_weight > 0 and s.rank > k_cap));
  ok := sel_before is not distinct from sel_after and n_bad = 0
        and (select coalesce(max(c), 0) <= 1 from (select count(*) c from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
                                                    where s.batch = b.batch and s.decoy_set = 0 and s.selected group by g.family, coalesce(g.sub, ''), g.source, g.metric, g.geo_kind) x)
        and (select count(*) from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = b.batch and s.decoy_set = 0 and s.selected and g.bh_weight > 0) <= k_cap;
  res := ripples._att_t(res, 'T41 selection rule pure and deterministic: re-run = same set; every selected row obeys n / p / threshold; one variant per pair; cap honoured', ok,
                        jsonb_build_object('n_selected', coalesce(cardinality(sel_before), 0), 'violations', n_bad));
  -- T42 confirmation BH over the confirmation set only
  select array_agg(s.grid_id order by s.grid_id), array_agg(coalesce(s.c_p, 1)::float8 order by s.grid_id) into ids, ps
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = b.batch and s.decoy_set = 0 and s.selected and g.bh_weight > 0 and s.c_n >= (rule ->> 'c_n_min')::int;
  ok := true;
  if ids is not null then
    qs := ripples.att_bh_q(ps, array_fill(1::float8, array[cardinality(ps)]));
    for i in 1..cardinality(ids) loop
      ok := ok and abs((select c_q from ripples.att_fx63_select where batch = b.batch and decoy_set = 0 and grid_id = ids[i]) - qs[i]) < 1e-6;
    end loop;
  end if;
  select count(*) into n_bad from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = b.batch and s.decoy_set = 0 and ((s.verdict = 'confirmed' and (coalesce(s.c_q, 1) > 0.05 or not s.c_sign_ok or g.bh_weight = 0))
                                                  or (s.verdict = 'confirmed (weaker)' and (coalesce(s.c_q, 1) > 0.20 or not s.c_sign_ok))
                                                  or (s.strength like 'confirmed%' and not s.selected));
  ok := ok and n_bad = 0;
  res := ripples._att_t(res, 'T42 confirmation BH recomputes over the confirmation set only (m = selected findings with ≥ K held-out events); confirmed ⇒ q ≤ 0.05, sign agrees, never a check', ok,
                        jsonb_build_object('m', coalesce(cardinality(ids), 0), 'bad_rows', n_bad));
  -- T43 tier isolation
  select pg_get_functiondef(p.oid) into hk from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname = 'att_fx_hook';
  ok := position($l$liftable text[] := array['q above 0.05', 'a placebo family disagrees', 'one channel only', 'placebo families', 'final look not reached']$l$ in hk) > 0
        and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%'
                          and (pg_get_functiondef(p.oid) ~ 'att_finalize\(' or pg_get_functiondef(p.oid) ~ 'att_hop_tests' or pg_get_functiondef(p.oid) ~ 'att_fx_hook\('))
        and not exists (select 1 from ripples.att_fx_grid where status = 'fx63' and ledger_seq is not null)
        and not exists (select 1 from jsonb_array_elements(public.rm_patterns(null, 'all')) x join ripples.att_fx_grid g on g.grid_id = (x ->> 'id')::int where g.status = 'fx63');
  res := ripples._att_t(res, 'T43 6.3 never touches 6.1/6.2 tiering: hook liftable set unchanged, no 6.3 function references att_finalize / att_hop_tests / att_fx_hook, 6.3 grid rows invisible to the hook and to rm_patterns', ok, null);
  -- T44 spike-in power on a synthetic 12-region daily panel (seeded): (a) a delayed effect (+0.10 from day 8 to day 21 after onset) is caught
  -- by the pre-registered delayed window (28 / 14 / lag 7) and missed by the immediate one (28 / 7 / 0); (b) sparse Poisson-like counts
  -- (λ = 0.3/day, +1.5/day for 14 days) are detected more strongly on the weekly-sum panel than on the daily panel.
  perform setseed(0.63);
  vals := array_fill(0::float8, array[nr, nd]);
  for r in 1..nr loop for t in 1..nd loop
    v := 5 + 0.3 * sin(2 * pi() * t / 365.0) + (random() - 0.5) * 0.2;
    if r = 1 and t between 500 + 7 and 500 + 20 then v := v + 0.10; end if;
    vals[r][t] := v;
  end loop; end loop;
  j := ripples._att_t63_prefix(vals);
  select array_agg(x::float8) into ps_a from jsonb_array_elements_text(j -> 'ps') x;   -- flattened; rebuild 2-D below
  ps_a := (select array_agg(x) from (select array(select (e ->> 0)::float8 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'ps') row_) q);
  pc_a := (select array_agg(x) from (select array(select (e ->> 0)::int2 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'pc') row_) q);
  x_imm := ripples.att_fx_did(ps_a, pc_a, array[1], array[2,3,4,5,6,7,8,9,10,11,12], 500, 28, 7, 0, 0.7);
  x_del := ripples.att_fx_did(ps_a, pc_a, array[1], array[2,3,4,5,6,7,8,9,10,11,12], 500, 28, 14, 7, 0.7);
  ok := abs(x_del[1] - 0.10) < 0.03 and abs(x_imm[1]) < 0.03 and abs(x_del[1]) > 2 * abs(x_imm[1]);
  -- (b) sparse counts, daily log1p vs weekly-sum log1p (att_fx_calc z on each, same events / same seed)
  perform setseed(0.64);
  for r in 1..nr loop for t in 1..nd loop
    lam := 0.3 + case when r = 1 and t between 500 and 513 then 1.5 else 0 end;
    v := 0; for i in 1..8 loop if random() < lam / 8.0 then v := v + 1; end if; end loop;   -- binomial(8, λ/8) ≈ Poisson(λ)
    vals[r][t] := ln(1 + v);
  end loop; end loop;
  j := ripples._att_t63_prefix(vals);
  ps_a := (select array_agg(x) from (select array(select (e ->> 0)::float8 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'ps') row_) q);
  pc_a := (select array_agg(x) from (select array(select (e ->> 0)::int2 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'pc') row_) q);
  select array_agg(('2018-01-01'::date + g)::date order by g) into days from generate_series(0, nd - 1) g;
  select array_agg('R' || g order by g) into regs from generate_series(1, nr) g;
  jd := ripples.att_fx_calc(ps_a, pc_a, days, regs, 'day', array['R1'], days[500], 28, 14, 0, false, 0.5, cfg -> 'explore');
  -- weekly sums of the same raw counts (exp(v) - 1), then log1p
  wvals := array_fill(0::float8, array[nr, nd / 7]);
  for r in 1..nr loop for t in 1..(nd / 7) loop
    v := 0; for i in 1..7 loop v := v + exp(vals[r][(t - 1) * 7 + i]) - 1; end loop;
    wvals[r][t] := ln(1 + v);
  end loop; end loop;
  j := ripples._att_t63_prefix(wvals);
  ps_a := (select array_agg(x) from (select array(select (e ->> 0)::float8 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'ps') row_) q);
  pc_a := (select array_agg(x) from (select array(select (e ->> 0)::int2 from jsonb_array_elements(row_) e) x from jsonb_array_elements(j -> 'pc') row_) q);
  select array_agg(('2018-01-01'::date + 7 * g + 6)::date order by g) into wdays from generate_series(0, nd / 7 - 1) g;
  jw := ripples.att_fx_calc(ps_a, pc_a, wdays, regs, 'week', array['R1'], wdays[72], 8, 2, 0, false, 0.5, cfg -> 'explore');
  z_day := (jd ->> 'z')::float8; z_week := (jw ->> 'z')::float8;
  ok := ok and z_day is not null and z_week is not null and z_week > 3 and z_day > 3;   -- both designs detect; the weekly/daily ratio is REPORTED, not asserted (iid counts: no gain)
  res := ripples._att_t(res, 'T44 spike-in power: delayed window recovers a delayed +0.10 the immediate window misses; daily and weekly-sum panels both detect a sparse-count spike (z ratio reported)', ok,
                        jsonb_build_object('d_immediate', round(x_imm[1]::numeric, 4), 'd_delayed', round(x_del[1]::numeric, 4), 'z_daily', round(z_day::numeric, 2), 'z_weekly', round(z_week::numeric, 2), 'z_weekly_over_daily', round((z_week / z_day)::numeric, 2),
                                           'p_space_daily', jd ->> 'p_space', 'p_space_weekly', jw ->> 'p_space'));
  -- T45 EB shrinkage
  ok := true; n_sh := 0;
  pool := (ripples.att_fx_dl(array[0.10, 0.30, -0.05], array[0.05, 0.05, 0.05]))[1];
  for sh in select * from ripples.att_fx63_shrink(array[0.10, 0.30, -0.05], array[0.05, 0.05, 0.05]) loop
    n_sh := n_sh + 1;
    ok := ok and sh.se_shrunk <= sh.se_raw + 1e-12 and ((sh.d_shrunk between least(sh.d_raw, pool) - 1e-9 and greatest(sh.d_raw, pool) + 1e-9)) and sh.w_pool between 0 and 1;
  end loop;
  ok := ok and n_sh = 3 and (select bool_and(abs(d_shrunk - 0.2) < 1e-9) from ripples.att_fx63_shrink(array[0.2, 0.2, 0.2], array[0.05, 0.05, 0.05]));
  res := ripples._att_t(res, 'T45 EB partial pooling: shrunk estimate lies between the raw and the pool, se never larger, τ² = 0 → full pooling', ok, jsonb_build_object('pool', round(pool::numeric, 4), 'n', n_sh));
  -- T46 decoy calibration on the ledger
  select s.v into cal from ripples.att_state s where s.k = 'engine63.calibration';
  ok := cal is not null and (cal -> 'decoy_pipeline' ->> 'n_decoy_selected')::int > 0
        and ((cal -> 'decoy_pipeline' -> 'wilson' ->> 0)::float8 <= 0.05)          -- the Wilson lower bound must not exclude the nominal 5 %
        and (cal -> 'tier_guard' ->> 'hook_liftable_unchanged')::boolean and (cal -> 'tier_guard' ->> 'no_63_function_touches_tiers')::boolean
        and exists (select 1 from ripples.att_ledger l where l.seq = b.calib_seq and l.kind = 'calibration');
  res := ripples._att_t(res, 'T46 decoy universes through the full split-sample pipeline: false-confirmation rate on the ledger, Wilson lower bound ≤ 5 %', ok, cal -> 'decoy_pipeline');
  -- T47 surprise fields
  ok := ripples.att_fx63_domain_distance('hazard', 'weather') = 0 and ripples.att_fx63_domain_distance('hazard', 'power') = 0.5 and ripples.att_fx63_domain_distance('hazard', 'labor') = 1
        and ripples.att_fx63_expected_by_mechanism('hazard.storm', 'fema.decl') and not ripples.att_fx63_expected_by_mechanism('hazard.quake', 'census.bfs')
        and not exists (select 1 from ripples.att_fx63_select where batch = b.batch and (domain_distance is null or expected_by_mechanism is null));
  res := ripples._att_t(res, 'T47 surprise fields: domain distance from the matrix, mechanism-library flag from the family mapper / graph, present on every row', ok, null);
  -- T48 no tier words in any 6.3 public output; hunches always labelled; common-shock failure not liftable
  txt := public.rm_patterns63(null, 'all')::text || public.rm_hunches(null, 200)::text;
  ok := txt !~* '"tier"' and txt !~* 'measured' and txt !~* '"likely"' and position('common shock day' in hk) = 0
        and not exists (select 1 from jsonb_array_elements(public.rm_hunches(null, 200)) h where h ->> 'label' <> 'hunch' or h ->> 'strength' <> 'hunch')
        and not exists (select 1 from jsonb_array_elements(public.rm_patterns63(null, 'confirmed')) p where p ->> 'strength' <> 'confirmed pattern');
  res := ripples._att_t(res, 'T48 Thanksgiving / tier guard: 6.3 public outputs carry no tier words, hunches are always labelled hunch, the common-shock failure is not in the hook''s liftable set', ok, null);
  -- T49 ledger
  lv := ripples.att_ledger_verify();
  ok := (lv ->> 'ok')::boolean
        and exists (select 1 from ripples.att_ledger where kind = 'model_version' and ref ->> 'method' = '6.3')
        and exists (select 1 from ripples.att_ledger where seq = b.explore_seq and kind = 'freeze' and ref ->> 'object' = 'fx_grid' and ref ->> 'method' like '6.3%' and ref ->> 'stage' = 'explore')
        and exists (select 1 from ripples.att_ledger where seq = b.confirm_seq and kind = 'freeze' and ref ->> 'object' = 'fx_grid' and ref ->> 'stage' = 'confirm')
        and b.explore_seq < b.confirm_seq
        and (select min(computed_at) from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like b.batch || '/%' and f.role = 'explore')
            > (select created_at from ripples.att_ledger where seq = b.explore_seq)
        and (select min(computed_at) from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like b.batch || '/%' and f.role = 'confirm')
            > (select created_at from ripples.att_ledger where seq = b.confirm_seq);
  res := ripples._att_t(res, 'T49 ledger: model_version 6.3, exploration + confirmation freezes (object fx_grid) before any effect of their stage was computed, att_ledger_verify ok', ok,
                        jsonb_build_object('verify', lv - 'bad' - 'rows', 'explore_seq', b.explore_seq, 'confirm_seq', b.confirm_seq));
  return jsonb_build_object('ok', (select bool_and((x ->> 'ok')::boolean) from jsonb_array_elements(res) x), 'tests', res);
end $$;
revoke all on function ripples.att_test_engine_63(text), ripples._att_t63_prefix(float8[][]) from anon, authenticated, public;
