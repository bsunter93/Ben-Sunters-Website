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

create or replace function ripples.att_test_engine(p_cleanup boolean default true) returns jsonb
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
        and (j3 ->> 'sd')::float8 < 1.5 and (s ->> 'sd')::float8 > 5 and (j3 ->> 'to')::date <= '2022-01-01'::date + 560 - 7 - 30 - 7;
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
  ok := true;
  for h in select l.seq, l.payload_hash fh, (l.ref ->> 'as_of')::date as_of, (l.ref ? 'refreeze_of') refrozen from ripples.att_ledger l
           where l.kind = 'freeze' and not (l.ref ? 'superseded_by') loop
    v_recomp := ripples.att_freeze_hash(h.as_of, false, h.fh);
    ok := ok and v_recomp = h.fh
          and (h.refrozen or abs((select sum(bh_weight) - count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)) < 1e-2 * greatest(1, (select count(*) from ripples.att_hop_candidates c where c.frozen_hash = h.fh)));
  end loop;
  res := ripples._att_t(res, 'T5 every frozen batch recomputes bit-identically and its BH weights sum to m', ok,
           (select jsonb_agg(jsonb_build_object('as_of', x.as_of, 'batches', x.b, 'm', x.m)) from (select as_of, count(distinct frozen_hash) b, count(*) m from ripples.att_hop_candidates where frozen_hash is not null group by as_of) x));
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
  ok := (ks ->> 'p')::float8 >= 0.05 and (select min(x) from unnest(ps) x) >= 1.0 / 201;
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
  ok := not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'library' and (c.l_by_channel is null or c.engine_version <> '6.1' or c.graph_version is null))
        and (select l_by_channel ->> 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop) = '7'
        and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = v_ev and c.role <> 'negative_control' group by c.as_of, c.event_id, c.parent_hop, c.node, c.sign having count(*) > 1)
        and not exists (select 1 from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id where c.event_id = v_ev and t.q_w is not null and t.look_no < 100
                        and abs((t.detail -> 'bh' ->> 'p_bh')::float8 - t.fluke::float8) > 1e-6)
        and (select every(sign <> 0) from ripples.att_hop_candidates c where c.event_id = v_ev and c.role = 'negative_control');
  res := ripples._att_t(res, 'T17 frozen L / versions on the batch, no duplicate paths, BH input = p_h, signed negative controls', ok,
           (select jsonb_build_object('l_by_channel', l_by_channel, 'engine_version', engine_version, 'graph_version', left(graph_version, 12)) from ripples.att_hop_candidates where hop_id = v_hop));

  -- T18 (B4, the audit's stop case) a storm with onset in Thanksgiving week 2025 over New York proposes the NYC transit targets (geo filter)
  -- and can NEVER reach Measured: the onset and the window's peak sit on registered common-shock days. Real data, real code path.
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

    if p_cleanup then raise exception using errcode = 'P0999', message = 'fixture rollback'; end if;
  exception when sqlstate 'P0999' then null;
  end;
  return jsonb_build_object('ok', not exists (select 1 from jsonb_array_elements(res) r where not (r ->> 'ok')::boolean), 'tests', res);
end $$;
revoke all on function ripples.att_test_engine(boolean) from anon, authenticated, public;

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
    r := ripples.att_test_engine(true);
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
