-- Unit + fixture tests for the Ripple Map cascade engine (WS-B). Run: select ripples.att_test_engine();  (service_role)
-- Covers: transforms (Φ, Φ⁻¹, NB mid-p, holidays), window statistic and CAR scaling, sd_null, weighted BH (pure), frozen BH weights and
-- the bit-identical freeze hash, tier logic on a synthetic fixture with known injected effects (recall, null uniformity, decoy FDR),
-- attention-only cap, MONEY/IO zero tests, placebo shift-0 identity, retraction, ledger chaining (incl. a tamper check in a savepoint).
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
begin
  -- T1 transforms
  ok := abs(ripples.att_norm_inv(0.975) - 1.959964) < 1e-4 and abs(ripples.att_norm_cdf(1.96) - 0.9750021) < 1e-5
        and abs(ripples.att_norm_cdf(ripples.att_norm_inv(0.001)) - 0.001) < 1e-6;
  res := ripples._att_t(res, 'T1 normal cdf/quantile', ok, jsonb_build_object('inv975', ripples.att_norm_inv(0.975), 'cdf196', ripples.att_norm_cdf(1.96)));
  ok := abs(ripples.att_nb_midp_z(5, 5, null)) < 0.25 and ripples.att_nb_midp_z(15, 5, null) > 3 and ripples.att_nb_midp_z(15, 5, 2) < ripples.att_nb_midp_z(15, 5, null)
        and ripples.att_nb_midp_z(5000, 3, null) > 6;
  res := ripples._att_t(res, 'T1 NB mid-p z (Poisson centre, tail, overdispersion, underflow)', ok,
           jsonb_build_object('z_5_5', ripples.att_nb_midp_z(5, 5, null), 'z_15_5', ripples.att_nb_midp_z(15, 5, null), 'z_15_5_r2', ripples.att_nb_midp_z(15, 5, 2), 'z_5000_3', ripples.att_nb_midp_z(5000, 3, null)));
  ok := ripples.att_holiday('2025-11-27') = 'us_thanksgiving' and ripples.att_holiday('2025-12-25') = 'xmas_week' and ripples.att_holiday('2026-04-03') = 'uk_goodfriday'
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

  -- T9 retraction: publish the top hop, then flag its onset as a common-shock day and re-finalise → retracted + ledger row
  insert into ripples.att_hop_registry(hop_id, window_close, p_hat, family, path_type, channel) select v_hop, window_close, 0.2, 'test.synth', path_type, 'PHYS' from ripples.att_hop_candidates where hop_id = v_hop
  on conflict (hop_id) do nothing;
  update ripples.att_hop_registry set published_tier = 'measured', published_at = now() where hop_id = v_hop;
  update ripples.att_hop_tests set common_shock = true, q_w = null where hop_id = v_hop and look_no = v_look;
  fin := ripples.att_finalize((select look_day from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look), true);
  ok := (select tier from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look) = 'retracted'
        and exists (select 1 from ripples.att_ledger where kind = 'retract' and (ref ->> 'hop_id')::bigint = v_hop);
  res := ripples._att_t(res, 'T9 retraction on a later common-shock flag (struck through, ledger row)', ok, jsonb_build_object('tier', (select tier from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look), 'reason', (select retract_reason from ripples.att_hop_tests where hop_id = v_hop and look_no = v_look)));

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
