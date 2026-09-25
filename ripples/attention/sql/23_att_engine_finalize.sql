-- Migration: att_engine_finalize (WS-B, Ripple Map v6, 2026-09-25)
-- ENGINE_SPEC §5.2 (one weighted BH over the day's looks, real + decoy together), §1.6 tiers with every Measured condition,
-- §5.4 decoy-calibrated fluke bins, §3.13 shrunk multiples, §4 chaining decisions, §6 hiddenness, §7 hysteresis / retraction /
-- ageing / post-publication freezing, §5.3 denominators and the CascadePayload (§11), plus att_expand (depth 2–3 candidates
-- staged for the next morning's freeze). Chain probabilities Π(1 − f) are computed inside att_expand only and never stored in a payload.
-- Depends on 20–22.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Helpers: hiddenness from the frozen candidate, shrunk multiple, fluke bins, weighted BH
-- ---------------------------------------------------------------------------------------------------------------------
-- H recovered from the frozen VOI = π(1−π)(0.5 + 0.5H)  (pre-onset structure only; never enters the test)
create or replace function ripples.att_hiddenness(p_hop bigint) returns real
language sql stable set search_path = '' as $$
  select least(1, greatest(0, ((c.voi / nullif(c.prior * (1 - c.prior), 0)) - 0.5) / 0.5))::real
  from ripples.att_hop_candidates c where c.hop_id = p_hop
$$;

-- Shrunk multiple (ENGINE §3.13): δ̃ = δ·τ²/(τ² + σ²_null); τ² = 4 until a channel has 30 real passes; ρ̃ = exp(δ̃·σ), 80 % interval
create or replace function ripples.att_shrunk_rho(p_channel text, p_delta float8, p_sd_null float8, p_sigma float8, p_value_kind text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare tau2 float8; n_pass int; v_var float8; s2 float8 := greatest(p_sd_null * p_sd_null, 1e-6); d float8; half float8;
begin
  select count(*), var_samp((t.s_by_channel -> p_channel ->> 'S')::float8) into n_pass, v_var
    from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
   where c.role = 'real' and t.tier in ('likely','measured') and t.look_day >= current_date - 90 and (t.s_by_channel -> p_channel ->> 'zhat')::float8 >= 3;
  tau2 := case when n_pass >= 30 and v_var is not null then greatest(0, v_var - s2) else 4 end;
  d := p_delta * tau2 / (tau2 + s2);
  half := 1.28 * sqrt(tau2 * s2 / (tau2 + s2));
  if p_value_kind = 'rate' then
    return jsonb_build_object('rho', d * p_sigma, 'lo', (d - half) * p_sigma, 'hi', (d + half) * p_sigma, 'raw', p_delta * p_sigma, 'unit', 'points', 'tau2', tau2, 'n_pass', n_pass);
  end if;
  return jsonb_build_object('rho', exp(d * p_sigma), 'lo', exp((d - half) * p_sigma), 'hi', exp((d + half) * p_sigma), 'raw', exp(p_delta * p_sigma), 'unit', 'x', 'tau2', tau2, 'n_pass', n_pass);
end $$;

create or replace function ripples.att_s_bin(p_t float8) returns text
language sql immutable set search_path = '' as $$
  select case when p_t is null or p_t < 3 then '<3' when p_t < 4 then '3-4' when p_t < 6 then '4-6' when p_t < 10 then '6-10' else '10+' end
$$;

-- Fluke bins over the trailing 90 days (ENGINE §5.4): pass = Likely+ (q_w ≤ 0.20); H-tercile dropped when decoy_tested in the cell < 200
create or replace function ripples.att_fluke_bins_refresh(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_decoy_total int; warming boolean;
begin
  delete from ripples.att_fluke_bins where as_of = p_as_of;
  drop table if exists _fb;
  create temp table _fb on commit drop as
  select t.hop_id, c.role, ripples.att_s_bin(t.t_stat) s_bin, t.h_bin, (t.q_w <= 0.20) pass
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.look_day between p_as_of - 90 and p_as_of and t.t_stat is not null and t.q_w is not null and c.role in ('real','decoy') and not c.reconstructed
    and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = t.hop_id and t2.q_w is not null and t2.look_day <= p_as_of);
  select count(*) into v_decoy_total from _fb where role = 'decoy';
  warming := v_decoy_total < 500;
  insert into ripples.att_fluke_bins(as_of, s_bin, h_bin, decoy_pass, decoy_tested, real_pass, real_tested, f, warming)
  select p_as_of, s_bin, hb, dp, dt, rp, rt,
         case when rt > 0 and rp > 0 and dt > 0 then least(1, (dp::float8 / dt) / (rp::float8 / rt)) when dt > 0 and rp = 0 then 1 end, warming
  from (
    select s_bin, coalesce(h_bin, 0) hb,
           sum(case when role = 'decoy' and pass then 1 else 0 end) dp, sum(case when role = 'decoy' then 1 else 0 end) dt,
           sum(case when role = 'real' and pass then 1 else 0 end) rp, sum(case when role = 'real' then 1 else 0 end) rt
    from _fb where s_bin <> '<3' and h_bin is not null group by s_bin, coalesce(h_bin, 0)
    union all
    select s_bin, 0, sum(case when role = 'decoy' and pass then 1 else 0 end), sum(case when role = 'decoy' then 1 else 0 end),
           sum(case when role = 'real' and pass then 1 else 0 end), sum(case when role = 'real' then 1 else 0 end)
    from _fb where s_bin <> '<3' group by s_bin) x
  on conflict (as_of, s_bin, h_bin) do update set decoy_pass = excluded.decoy_pass, decoy_tested = excluded.decoy_tested,
    real_pass = excluded.real_pass, real_tested = excluded.real_tested, f = excluded.f, warming = excluded.warming;
  drop table _fb;
  return jsonb_build_object('as_of', p_as_of, 'decoy_tested', v_decoy_total, 'warming', warming);
end $$;

-- f for a (T, H) pair from the latest bins: the H-stratified cell when its decoy_tested ≥ 200, else the pooled S-bin; null → warming
create or replace function ripples.att_fluke_lookup(p_as_of date, p_t float8, p_hbin int) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('f', b.f, 'bin', b.s_bin || ' × H' || b.h_bin, 'warming', b.warming, 'decoy_tested', b.decoy_tested)
       from ripples.att_fluke_bins b where b.as_of = p_as_of and b.s_bin = ripples.att_s_bin(p_t) and b.h_bin = p_hbin and b.decoy_tested >= 200 limit 1),
    (select jsonb_build_object('f', b.f, 'bin', b.s_bin, 'warming', b.warming, 'decoy_tested', b.decoy_tested)
       from ripples.att_fluke_bins b where b.as_of = p_as_of and b.s_bin = ripples.att_s_bin(p_t) and b.h_bin = 0 limit 1),
    jsonb_build_object('f', null, 'bin', ripples.att_s_bin(p_t), 'warming', true, 'decoy_tested', 0))
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. att_finalize (ENGINE §5.2, §1.6, §7)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_finalize(p_as_of date, p_library boolean default false) returns jsonb
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
begin
  -- the day's family: every hop's latest look with a statistic that is not yet finalised, or that looked today
  drop table if exists _fin; drop table if exists _bh; drop table if exists _q; drop table if exists _nf;
  create temp table _fin on commit drop as
  select t.hop_id, t.look_no, t.t_stat, t.fluke p_h, t.p_date, t.n_date, t.s_pre, c.bh_weight, c.role, c.event_id, c.depth, c.parent_hop, c.path_type, c.channels, c.window_close, c.looks,
         t.is_final, t.look_day, c.prior,
         -- BH input: the date family (the only family with the 2,000-draw resolution; ENGINE §5.1); p_h = max over families stays the gate
         case when coalesce(t.n_date, 0) >= 30 and t.p_date is not null then t.p_date else t.fluke end p_bh
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.t_stat is not null and t.fluke is not null and c.frozen_hash is not null and c.reconstructed = p_library and t.look_day <= p_as_of
    and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = t.hop_id and t2.t_stat is not null and t2.look_day <= p_as_of)
    and (t.q_w is null or t.look_day = p_as_of or exists (select 1 from ripples.att_hop_candidates c2 where c2.hop_id = c.hop_id and c2.as_of = p_as_of));
  select count(*) into m from _fin;

  -- looks with a statistic but no placebo family of ≥ 30 draws carry no p-value: they never enter BH and resolve as watching (interim)
  -- or flat (final) with the reason named; they still count in the day's denominators (p taken as 1, the conservative reading)
  drop table if exists _nf;
  create temp table _nf on commit drop as
  select t.hop_id, t.look_no, t.is_final, t.look_day, c.window_close, c.event_id
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.t_stat is not null and t.fluke is null and t.tier is null and c.frozen_hash is not null and c.reconstructed = p_library and t.look_day <= p_as_of;
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
    ext := ripples.att_run_placebos(r.hop_id, 'date', top_draws, r.look_no, r.t_stat, true, coalesce(r.s_pre, 0) < 2);
    if (ext ->> 'n')::int >= 30 then
      update ripples.att_hop_tests t set p_date = (ext ->> 'p')::real, n_date = (ext ->> 'n')::int,
             placebo = coalesce(t.placebo, '{}'::jsonb) || jsonb_build_object('date', ext - 't_h'),
             fluke = greatest(coalesce(case when n_link >= 30 then p_link end, 0), coalesce(case when n_topic >= 30 then p_topic end, 0), (ext ->> 'p')::real),
             p_floor = least(coalesce(p_floor, 1), 1.0 / (1 + (ext ->> 'n')::int))
       where t.hop_id = r.hop_id and t.look_no = r.look_no;
      update _fin f set p_h = t.fluke, p_bh = t.p_date, p_date = t.p_date, n_date = t.n_date from ripples.att_hop_tests t where t.hop_id = f.hop_id and t.look_no = f.look_no and f.hop_id = r.hop_id;
    end if;
  end loop;

  -- one weighted BH over the actual family (frozen weights, renormalised so Σw = m over the hops in this run; Genovese–Roeder–Wasserman);
  -- real + decoy + controls in the same run
  create temp table _bh on commit drop as
  select hop_id, look_no, p_bh, w, p_bh / w pw, row_number() over (order by p_bh / w, hop_id) rk
  from (select f.*, coalesce(f.bh_weight, 1) * m / sum(coalesce(f.bh_weight, 1)) over () w from _fin f) x;
  create temp table _q on commit drop as
  select hop_id, look_no, least(1, min(m * pw / rk) over (order by rk desc rows between unbounded preceding and current row)) q_w, w from _bh;
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
    select tier into prev_tier from ripples.att_hop_tests t where t.hop_id = r.hop_id and t.look_no < r.look_no and t.tier is not null order by look_no desc limit 1;
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
    foreach ch in array v_agree loop
      longest_final := greatest(coalesce(longest_final, '1900-01-01'::date), (select max(d) from unnest(ripples.att_look_dates(ch, (select onset from ripples.att_hop_candidates where hop_id = r.hop_id), ripples.att_l_days(ch))) d));
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
    -- rarity gate across families: p_h = max_f p_f must be ≤ 0.05 for Measured (≤ 0.20 for Likely), which is what the spec's p_h-based
    -- BH implied; BH itself runs on the date family, the only one with the 2,000-draw resolution
    if coalesce(r.p_h, 1) > q_meas then fails := array_append(fails, 'a placebo family disagrees'); end if;
    if not (r.q_w <= q_meas) then fails := array_append(fails, 'q above 0.05');
    elsif not v_final_agree then fails := array_append(fails, 'final look not reached'); end if;
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
    -- registry resolution at the final look
    if r.is_final then
      update ripples.att_hop_registry g set resolved_at = coalesce(g.resolved_at, now()), hit = v_tier in ('likely','measured'), final_tier = v_tier where g.hop_id = r.hop_id;
      update ripples.att_hop_candidates set status = 'tested' where hop_id = r.hop_id;
    end if;
  end loop;

  -- day line + ledger resolve row (hash of the day's tier assignments)
  select jsonb_agg(jsonb_build_array(t.hop_id, t.look_no, t.tier, round(t.q_w::numeric, 6), round(coalesce(t.f, -1)::numeric, 4)) order by t.hop_id) into tiers
    from ripples.att_hop_tests t join _fin f on f.hop_id = t.hop_id and f.look_no = t.look_no;
  v_seq := ripples.att_ledger_append(p_as_of, 'resolve', jsonb_build_object('as_of', p_as_of, 'm', m, 'library', p_library),
             jsonb_build_object('as_of', p_as_of, 'tiers', tiers, 'line', jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_flukes', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3))));
  perform ripples.att_state_set('engine.day.' || p_as_of, jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_flukes', round(sum_f::numeric, 3),
                                'sum_p', round(sum_p::numeric, 3), 'flat', n_flat, 'watching', n_watch, 'retracted', n_retract, 'ledger_seq', v_seq, 'warming', warming));
  -- event status and cascade payloads for every event touched today
  for e in select distinct event_id from _fin union select distinct event_id from _nf loop
    perform ripples.att_event_status(e.event_id, p_as_of);
    perform ripples.att_build_cascade(e.event_id, p_as_of);
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'flat', n_flat, 'watching', n_watch,
                            'retracted', n_retract, 'expected_flukes', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3), 'warming', warming, 'ledger_seq', v_seq);
end $$;

-- Event status (ENGINE §1.5 / §7 ageing): running | ended | nowhere | archived
create or replace function ripples.att_event_status(p_event bigint, p_as_of date) returns text
language plpgsql security definer set search_path = '' as $$
declare v_open boolean; v_any boolean; v_last date; v_slow boolean; st text;
begin
  select bool_or(c.window_close >= p_as_of), max(c.window_close),
         bool_or(exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel in ('JOBS','INST','ECON')))
    into v_open, v_last, v_slow
    from ripples.att_hop_candidates c where c.event_id = p_event and c.frozen_hash is not null;
  select bool_or(t.tier in ('likely','measured')) into v_any
    from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id where c.event_id = p_event;
  st := case when coalesce(v_open, false) then 'running'
             when v_last is not null and p_as_of > v_last + (case when coalesce(v_slow, false) then 90 else 30 end) then 'archived'
             when coalesce(v_any, false) then 'ended' else 'nowhere' end;
  update ripples.att_events set status = st where event_id = p_event;
  return st;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Cascade payload (ENGINE §11 CascadePayload): latest state in att_cascades; versions are frozen by WS-C's att_publish_cascades
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_domain_of(p_channel text) returns text
language sql immutable set search_path = '' as $$
  select case p_channel when 'READ' then 'reading' when 'SRCH' then 'search' when 'SOC' then 'social' when 'NEWS' then 'news' when 'TV' then 'news'
                        when 'PM' then 'markets' when 'BLD' then 'builders' when 'CONS' then 'consumption' when 'PHYS' then 'real_world'
                        when 'JOBS' then 'jobs' when 'INST' then 'institutions' when 'ECON' then 'economy' else 'other' end
$$;

-- ×normal spark and band for a series over the last p_days days ending p_end (from att_zvec resid; band = ±1.28σ with σ the series'
-- current robust scale, ENGINE §10.2 stores σ as a scalar)
create or replace function ripples.att_spark(p_series bigint, p_end date, p_days int default 60) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'spark', (select jsonb_agg(case when z.value_kind = 'rate' then round(coalesce(z.resid[i], 0)::numeric, 3) else round(exp(coalesce(z.resid[i], 0))::numeric, 3) end order by i)
              from generate_series(greatest(1, (p_end - z.from_day) + 1 - p_days + 1), least(z.n, (p_end - z.from_day) + 1)) i),
    'band', jsonb_build_object(
      'lo', (select jsonb_agg(case when z.value_kind = 'rate' then round((-1.28 * z.sigma)::numeric, 3) else round(exp(-1.28 * z.sigma)::numeric, 3) end order by i)
             from generate_series(greatest(1, (p_end - z.from_day) + 1 - p_days + 1), least(z.n, (p_end - z.from_day) + 1)) i),
      'hi', (select jsonb_agg(case when z.value_kind = 'rate' then round((1.28 * z.sigma)::numeric, 3) else round(exp(1.28 * z.sigma)::numeric, 3) end order by i)
             from generate_series(greatest(1, (p_end - z.from_day) + 1 - p_days + 1), least(z.n, (p_end - z.from_day) + 1)) i),
      'sigma', z.sigma, 'note', 'band = ±1.28σ, σ = current robust scale of the series'),
    'from', z.from_day + greatest(0, (p_end - z.from_day) - p_days + 1), 'unit', case when z.value_kind = 'rate' then 'points' else 'x' end)
  from ripples.att_zvec z where z.series_id = p_series and z.grain = 'day'
$$;

create or replace function ripples.att_node_label(p_node text) returns text
language sql stable set search_path = '' as $$
  select coalesce((select label from ripples.att_topics where qid = p_node),
                  (select label from ripples.att_topics where label_key = 'node:' || p_node), p_node)
$$;

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
    f1 := case when r.f > 0 then least(50, floor(1 / r.f)::int) end;
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
              'hidden', r.h_score, 'flags', to_jsonb(r.flags));
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
    'denominators', jsonb_build_object('tested', n_tested, 'moved', n_moved, 'measured', n_meas, 'expected_false_links', round(sum_f::numeric, 3), 'sum_p', round(sum_p::numeric, 3)),
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

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. att_expand (ENGINE §4): depth 2–3 candidates from Likely+ parents, staged for the next morning's freeze; fork_check candidates
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_expand(p_as_of date, p_library boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; n_fork int := 0; chain_f float8; ph bigint; f_i float8; nxt date := p_as_of + 1; ev record; k int; v_onset date;
        n_par int; beam int := 3;
begin
  for ev in select distinct c.event_id from ripples.att_hop_candidates c where c.frozen_hash is not null and c.reconstructed = p_library
             and c.role in ('real','decoy') and exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier in ('likely','measured')) loop
    n_par := 0;
    for r in
      select c.hop_id, c.node, c.depth, c.parent_hop, t.t_v, t.f, t.tier, t.t_stat
      from ripples.att_hop_candidates c
      join lateral (select * from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier is not null order by look_no desc limit 1) t on true
      where c.event_id = ev.event_id and c.frozen_hash is not null and t.tier in ('likely','measured') and c.depth < 3
        and not exists (select 1 from ripples.att_hop_candidates ch where ch.parent_hop = c.hop_id)
        and not exists (select 1 from ripples.att_cand_stage s where s.parent_hop = c.hop_id)
      order by (t.tier = 'measured') desc, t.t_stat desc
    loop
      exit when n_par >= beam;
      -- internal compounding Π(1 − f_i) along the chain: stop expanding below 0.5 (never exported)
      chain_f := 1; ph := r.hop_id;
      while ph is not null loop
        select t.f, c.parent_hop into f_i, ph from ripples.att_hop_candidates c
          join lateral (select f from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier is not null order by look_no desc limit 1) t on true
          where c.hop_id = ph;
        chain_f := chain_f * (1 - coalesce(f_i, 0.5));
      end loop;
      continue when chain_f < 0.5;
      v_onset := coalesce(r.t_v, (select onset from ripples.att_hop_candidates where hop_id = r.hop_id));
      k := ripples.att_gen_candidates(ev.event_id, nxt, r.hop_id, r.depth + 1, r.node, v_onset);
      -- beam: ≤ 20 candidates per parent (highest rank in path first)
      delete from ripples.att_cand_stage s using (
        select ctid, row_number() over (partition by parent_hop order by rank_in_path, path_type) rn from ripples.att_cand_stage where as_of = nxt and parent_hop = r.hop_id) d
      where s.ctid = d.ctid and d.rn > 20;
      -- fork checks: u → w direct for each staged child w without a depth-1 candidate
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, onset, rank_in_path, aware, jumps)
      select nxt, ev.event_id, 'fork_check', null, 1, e.topic_id, s.node,
             jsonb_build_array(jsonb_build_object('type','MAP','from',e.qid,'to',s.node,'sign',s.sign,'s',1.0,'source','fork check')), 'P-FORK', s.sign, e.onset, 99, 0, 1
      from ripples.att_cand_stage s join ripples.att_events e on e.event_id = ev.event_id
      where s.as_of = nxt and s.parent_hop = r.hop_id
        and not exists (select 1 from ripples.att_hop_candidates c1 where c1.event_id = ev.event_id and c1.depth = 1 and c1.node = s.node)
        and not exists (select 1 from ripples.att_cand_stage s2 where s2.as_of = nxt and s2.event_id = ev.event_id and s2.depth = 1 and s2.node = s.node);
      get diagnostics k = row_count; n_fork := n_fork + k;
      n := n + (select count(*) from ripples.att_cand_stage where as_of = nxt and parent_hop = r.hop_id);
      n_par := n_par + 1;
    end loop;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'staged_for', nxt, 'children', n, 'fork_checks', n_fork);
end $$;

-- Chaining decisions after depth ≥ 2 looks (ENGINE §4.2–4.4): order, fork test, mediation → fork_of / common_cause in detail
create or replace function ripples.att_chain_decide(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; fk record; v_fork boolean; v_med boolean; t_u date; t_v date; t_w date; pc jsonb;
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
    -- fork test: the direct u → w candidate (depth-1 or fork_check)
    select c1.hop_id, t1.t_stat, t1.lag_days into fk from ripples.att_hop_candidates c1
      join lateral (select * from ripples.att_hop_tests t1 where t1.hop_id = c1.hop_id and t1.t_stat is not null order by look_no desc limit 1) t1 on true
      where c1.event_id = r.event_id and c1.depth = 1 and c1.node = r.node and c1.role in ('real','decoy','fork_check') limit 1;
    v_fork := fk.hop_id is not null and ((fk.lag_days is not null and r.lag_days is not null and fk.lag_days <= r.lag_days + (t_v - t_u)) or coalesce(fk.t_stat, 0) >= 0.8 * r.t_stat);
    -- mediation (c): v → w has a MECH/MAP edge that u → w does not
    v_med := exists (select 1 from jsonb_array_elements(r.path) p where p ->> 'type' in ('MECH','MAP'))
             and not exists (select 1 from ripples.att_hop_candidates c1, jsonb_array_elements(c1.path) p where c1.event_id = r.event_id and c1.depth = 1 and c1.node = r.node and p ->> 'type' in ('MECH','MAP'));
    pc := jsonb_build_object('fork_test', v_fork, 'mediation_c', v_med, 'direct_hop', fk.hop_id);
    if v_fork or not v_med then
      update ripples.att_hop_tests t set detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('fork_of', r.event_id, 'chain', pc) where t.hop_id = r.hop_id and t.look_no = r.look_no;
    else
      update ripples.att_hop_tests t set detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('fork_of', null, 'chain', pc) where t.hop_id = r.hop_id and t.look_no = r.look_no;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
