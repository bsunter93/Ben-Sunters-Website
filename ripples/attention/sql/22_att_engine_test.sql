-- Migration: att_engine_test (WS-B, Ripple Map v6, 2026-09-25)
-- ENGINE_SPEC §3 (single-hop test: window statistic per channel, onset/lag, pre-trend, sd_null standardisation, combined T with
-- proposing-channel exclusion and shrunk R, linkage kind, LOSO, attribution rivals) and §5.1 (three placebo families through the
-- identical code path, Besag–Clifford stopping). One look = one att_hop_tests row (hop_id, look_no). Jobs run inside att_tick('hops').
-- Depends on 20_att_engine_zvec.sql and 21_att_engine_freeze.sql.

alter table ripples.att_hop_tests drop constraint if exists att_hop_tests_link_kind_check;
alter table ripples.att_hop_tests add constraint att_hop_tests_link_kind_check
  check (link_kind is null or link_kind in ('mechanism','measured','structural','comention','tv','newsroom','search','none'));
alter table ripples.att_hop_tests alter column t_u drop not null;
alter table ripples.att_hop_tests alter column as_of drop not null;
alter table ripples.att_hop_tests alter column u_topic drop not null;
alter table ripples.att_hop_tests alter column v_topic drop not null;
alter table ripples.att_sd_null add column if not exists mu real not null default 0;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Array-level primitives (pure; the same functions serve the real hop, every placebo draw and the spike-in power curves)
-- ---------------------------------------------------------------------------------------------------------------------
-- Window statistic over an AR array. p_kind 'peak' | 'car'; p_sign −1/0/+1 (0 = unsigned, two-sided); window [t_p, min(t_p+L, t_end)].
-- Returns {"S", "n", "peak_day", "onset", "lag", "sum", "rho_peak"}; S is null when the window has no observed day.
create or replace function ripples.att_win_stat(p_ar real[], p_resid real[], p_from date, p_n int, p_tp date, p_l int, p_kind text,
                                                p_sign int, p_rho1 float8, p_end date, p_attention boolean) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare i0 int; i1 int; i int; v float8; s float8; best float8 := null; best_i int; cnt int := 0; tot float8 := 0; onset_i int := null;
        thr_ok boolean; rp float8;
begin
  i0 := (p_tp - p_from) + 1; i1 := (least(p_tp + p_l, p_end) - p_from) + 1;
  if i1 < 1 or i0 > p_n or i1 < i0 then return jsonb_build_object('S', null, 'n', 0); end if;
  i0 := greatest(i0, 1); i1 := least(i1, p_n);
  for i in i0..i1 loop
    v := p_ar[i];
    continue when v is null;
    cnt := cnt + 1;
    s := case when p_sign = 0 then abs(v) else p_sign * v end;
    tot := tot + s;
    if best is null or s > best then best := s; best_i := i; end if;
  end loop;
  -- onset: first day in [t_p − 1, window end] with the signed AR ≥ 3 (attention: and ratio ≥ 1.5)
  for i in greatest(i0 - 1, 1)..i1 loop
    v := p_ar[i];
    continue when v is null;
    s := case when p_sign = 0 then abs(v) else p_sign * v end;
    thr_ok := s >= 3;
    if thr_ok and p_attention and p_resid is not null then thr_ok := exp(coalesce(p_resid[i], 0)) >= 1.5; end if;
    if thr_ok then onset_i := i; exit; end if;
  end loop;
  if cnt = 0 then return jsonb_build_object('S', null, 'n', 0); end if;
  rp := case when p_resid is not null and best_i is not null then p_resid[best_i] end;
  return jsonb_build_object(
    'S', case when p_kind = 'car' then tot / (sqrt(cnt) * sqrt((1 + p_rho1) / (1 - p_rho1))) else best end,
    'n', cnt, 'peak_day', p_from + (best_i - 1), 'sum', tot,
    'onset', case when onset_i is not null then p_from + (onset_i - 1) end,
    'lag', case when onset_i is not null then (p_from + (onset_i - 1)) - p_tp end,
    'rho_peak', rp);
end $$;

-- lag-1 autocorrelation of AR over the baseline B = [t_p − 111, t_p − 21], clamped to [−0.5, 0.9]
create or replace function ripples.att_rho1(p_ar real[], p_from date, p_n int, p_tp date) returns float8
language plpgsql immutable set search_path = '' as $$
declare i0 int; i1 int; i int; sx float8 := 0; cnt int := 0; mu float8; a float8; b float8; num float8 := 0; den float8 := 0;
begin
  i0 := greatest((p_tp - 111 - p_from) + 1, 1); i1 := least((p_tp - 21 - p_from) + 1, p_n);
  if i1 - i0 < 10 then return 0; end if;
  for i in i0..i1 loop if p_ar[i] is not null then sx := sx + p_ar[i]; cnt := cnt + 1; end if; end loop;
  if cnt < 10 then return 0; end if;
  mu := sx / cnt;
  for i in i0..i1 - 1 loop
    a := p_ar[i]; b := p_ar[i + 1];
    if a is not null then den := den + (a - mu) * (a - mu); end if;
    if a is not null and b is not null then num := num + (a - mu) * (b - mu); end if;
  end loop;
  if den <= 0 then return 0; end if;
  return least(0.9, greatest(-0.5, num / den));
end $$;

-- Null sd of the window statistic for a series: S over every full window start in its history (weekday-blind marginal null)
create or replace function ripples.att_sd_null_calc(p_ar real[], p_from date, p_n int, p_l int, p_kind text, p_sign int) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare t date; s jsonb; v float8; sx float8 := 0; sxx float8 := 0; cnt int := 0; rho float8; step int;
begin
  step := case when p_n > 1000 then 3 else 1 end;
  t := p_from + 112;
  while t <= p_from + p_n - 1 - p_l loop
    rho := case when p_kind = 'car' then ripples.att_rho1(p_ar, p_from, p_n, t) else 0 end;
    s := ripples.att_win_stat(p_ar, null, p_from, p_n, t, p_l, p_kind, p_sign, rho, p_from + p_n - 1, false);
    v := (s ->> 'S')::float8;
    if v is not null and (s ->> 'n')::int >= greatest(1, (p_l + 1) / 2) then sx := sx + v; sxx := sxx + v * v; cnt := cnt + 1; end if;
    t := t + step;
  end loop;
  if cnt < 20 then return jsonb_build_object('sd', null, 'n', cnt); end if;
  return jsonb_build_object('sd', sqrt(greatest(sxx / cnt - (sx / cnt) * (sx / cnt), 1e-6)), 'mean', sx / cnt, 'n', cnt);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Hop bundle in a session temp table (_hb) so every draw is an array slice
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_hb_load(p_series bigint[]) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  create temp table if not exists _hb (series_id bigint primary key, source text, channel text, kappa real, quality real, from_day date, n int,
                                       ar real[], resid real[], ar_agg real[], grain text, value_kind text, stat_kind text, l int, attention boolean,
                                       base_level real) on commit drop;
  insert into _hb
  select z.series_id, s.source, ripples.att_series_channel(z.series_id), z.kappa,
         coalesce(src.quality, 1) * 0.5,
         z.from_day, z.n, z.ar, z.resid, z.ar_agg, z.grain, z.value_kind, cs.stat_kind, ripples.att_l_days(cs.channel), cs.kind = 'attention', z.base_level
  from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id join ripples.att_sources src on src.source = s.source
  join ripples.att_channel_stat cs on cs.channel = ripples.att_series_channel(z.series_id)
  where z.series_id = any(p_series) and cs.channel <> 'MONEY'
  on conflict (series_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- sd_null (and its mean) for a loaded series (cache in att_sd_null, refreshed weekly). ž = (S − μ_null)/sd_null (22b: centred, the
-- more conservative reading of ENGINE §3.8 and the scale the LR = exp(3T − 4.5) formula assumes).
create or replace function ripples.att_sd_null_get(p_series bigint, p_kind text, p_l int, p_sign int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v real; m real; j jsonb; b record; v_sided text := case p_sign when 0 then 'abs' when -1 then '-' else '+' end;
begin
  select sd, mu into v, m from ripples.att_sd_null n where n.series_id = p_series and n.stat_kind = p_kind and n.w_len = p_l and n.sided = v_sided
    and n.as_of >= current_date - 7;
  if v is not null then return jsonb_build_object('sd', v, 'mu', m); end if;
  select * into b from _hb where series_id = p_series;
  if not found then return null; end if;
  j := ripples.att_sd_null_calc(b.ar, b.from_day, b.n, p_l, p_kind, p_sign);
  v := (j ->> 'sd')::real; m := coalesce((j ->> 'mean')::real, 0);
  if v is null then return null; end if;
  insert into ripples.att_sd_null(series_id, stat_kind, w_len, sided, sd, mu, n, as_of) values (p_series, p_kind, p_l, v_sided, v, m, (j ->> 'n')::int, current_date)
  on conflict (series_id, stat_kind, w_len, sided) do update set sd = excluded.sd, mu = excluded.mu, n = excluded.n, as_of = excluded.as_of;
  return jsonb_build_object('sd', v, 'mu', m);
end $$;

-- release-look statistic for weekly/monthly series: z of the first period overlapping [t_p, t_p + L] that is present (released)
create or replace function ripples.att_release_stat(p_ar real[], p_resid real[], p_from date, p_n int, p_grain text, p_tp date, p_l int, p_sign int, p_end date) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare i int; pstart date; pend date; v float8; s float8;
begin
  for i in 1..p_n loop
    pstart := case when p_grain = 'month' then (p_from + make_interval(months => i - 1))::date else p_from + 7 * (i - 1) end;
    pend := case when p_grain = 'month' then (p_from + make_interval(months => i))::date - 1 else pstart + 6 end;
    if pend < p_tp then continue; end if;
    if pstart > p_tp + p_l then exit; end if;
    if pstart > p_end then exit; end if;
    v := p_ar[i];
    if v is null then continue; end if;
    s := case when p_sign = 0 then abs(v) else p_sign * v end;
    return jsonb_build_object('S', s, 'n', 1, 'peak_day', pstart, 'onset', case when s >= 3 then pstart end,
                              'lag', case when s >= 3 then pstart - p_tp end, 'rho_peak', p_resid[i]);
  end loop;
  return jsonb_build_object('S', null, 'n', 0);
end $$;

-- Shrunk channel correlation R = 0.8·R̂ + 0.2·I (att_channel_corr; default R̂: 0.5 between attention channels, 0 elsewhere)
create or replace function ripples.att_channel_r(p_a text, p_b text) returns float8
language sql stable set search_path = '' as $$
  select case when p_a = p_b then 1.0 else
    0.8 * coalesce((select c.r[array_position(c.channels, p_a)][array_position(c.channels, p_b)]
                    from ripples.att_channel_corr c where p_a = any(c.channels) and p_b = any(c.channels) order by c.as_of desc limit 1),
                   case when (select kind from ripples.att_channel_stat where channel = p_a) = 'attention'
                         and (select kind from ripples.att_channel_stat where channel = p_b) = 'attention' then 0.5 else 0.0 end) end
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Combined statistic for a bundle at an onset (the ONE code path: real hop, date/link/topic draws, rivals, LOSO, spike-ins)
-- ---------------------------------------------------------------------------------------------------------------------
-- p_bundle: [{"series_id":..,"channel":..}] (series must be loaded in _hb); p_excl: excluded (proposing) channels;
-- p_drop: source to leave out (LOSO); p_agg: use aggregate-demeaned AR where available.
create or replace function ripples.att_hop_stat_b(p_bundle jsonb, p_tp date, p_end date, p_sign int, p_excl text[], p_drop text default null,
                                                  p_agg boolean default false, p_pre boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare it jsonb; b record; st jsonb; pre jsonb; sdj jsonb; sd real; mu real; rho float8; zs float8; zpre float8; ar real[];
        ch jsonb := '{}'::jsonb; c text; cw jsonb; num float8 := 0; den float8 := 0; keys text[]; i int; j int; wi float8;
        t float8; n3 int := 0; n3out int := 0; agree text[] := '{}'; v_onset date := null; v_lag int := null; spre float8 := 0;
        srcs text[] := '{}'; v_kind text; v_l int; v_att boolean; kmin real := null;
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
      sdj := ripples.att_sd_null_get(b.series_id, v_kind, v_l, p_sign);
      sd := (sdj ->> 'sd')::real; mu := coalesce((sdj ->> 'mu')::real, 0);
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
  if ch = '{}'::jsonb then return jsonb_build_object('T', null, 'channels', '{}'::jsonb, 'n_ch', 0); end if;
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
      den := den + (ch -> keys[i] ->> 'w')::float8 * (ch -> keys[j] ->> 'w')::float8 * ripples.att_channel_r(keys[i], keys[j]);
    end loop;
  end loop;
  t := case when den > 0 then num / sqrt(den) end;
  if v_onset is not null then v_lag := v_onset - p_tp; end if;
  return jsonb_build_object('T', t, 'channels', ch, 'n_ch', cardinality(keys), 'n_ch3', n3, 'n_out3', n3out, 'agree', to_jsonb(agree),
                            'onset', v_onset, 'lag', v_lag, 's_pre', spre, 'kappa_min', kmin,
                            'sources', to_jsonb((select array_agg(distinct s) from unnest(srcs) s)));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Draw specifications (deterministic; ENGINE §5.1) and att_test_hop
-- ---------------------------------------------------------------------------------------------------------------------
-- Date family: fake onsets on every day of [as_of − 730, as_of − 30] (full history, up to 2,555 days, for ≥ 3-year series), ≥ 30 d from
-- known onsets of the parent or the node, always t_p − 364 and t_p − 371; PHYS/ECON: season-matched draws (±21 d of t_p in prior years) first.
-- Daily (not weekly) shifts are what make the spec's 2,000-draw extension (p floor 0.0005) reachable; the AR arrays are already
-- weekday-adjusted, and the deterministic hash order spreads the 200 default draws over the whole range.
create or replace function ripples.att_date_draws(p_hop bigint, p_max int) returns date[]
language plpgsql stable security definer set search_path = '' as $$
declare c record; lo date; hi date; hist_from date; n_long int; d date; out date[] := '{}'; season date[] := '{}'; rest date[] := '{}';
        known date[]; v_l int; seas boolean; k int; first_all date; first_any date;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  select min(z.from_day), count(*) filter (where z.n > 1000) into hist_from, n_long
    from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id where ns.node = c.node and z.grain = 'day';
  v_l := coalesce(c.window_close - c.onset, 7);
  hi := c.as_of - 30 - v_l;
  lo := case when n_long > 0 then greatest(hist_from + 112, c.as_of - 2555) else c.as_of - 730 end;
  -- start where the bundle actually has an abnormal response (young series): every series valid if that leaves ≥ 60 days, else any series
  select max(f), min(f) into first_all, first_any
    from (select z.from_day + (min(u.o) - 1)::int f from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
          cross join lateral unnest(z.ar) with ordinality u(v, o)
          where ns.node = c.node and z.grain = 'day' and u.v is not null group by z.series_id) x;
  if first_all is not null then
    lo := greatest(lo, case when hi - first_all >= 60 then first_all else coalesce(first_any, first_all) end);
  end if;
  seas := exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel in ('PHYS','ECON'));
  -- known onsets of the parent topic / node topic (real events) → excluded ±30 d
  select coalesce(array_agg(e.onset), '{}') into known from ripples.att_events e
   where e.role = 'real' and (e.topic_id = c.u_topic or e.topic_id = c.v_topic);
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

-- Link family: real (live or library) events of other families with onset within ±7 d of t_p (each paired with the real node)
create or replace function ripples.att_link_draws(p_hop bigint, p_max int) returns bigint[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select array_agg(x.event_id order by x.o) from (
    select e.event_id, row_number() over (order by encode(extensions.digest(e.event_id::text || p_hop::text, 'sha256'), 'hex')) o
    from ripples.att_hop_candidates c join ripples.att_events u on u.event_id = c.event_id
    join ripples.att_events e on e.role in ('real','library') and e.event_id <> u.event_id and e.family <> u.family
         and abs(e.onset - c.onset) <= 7 and e.topic_id is distinct from c.v_topic
    where c.hop_id = p_hop) x where x.o <= p_max), '{}')
$$;

-- Topic family: per bundle series, matched same-source same-kind series (same baseline decile, coverage Jaccard ≥ 0.8) → a replacement bundle per draw
create or replace function ripples.att_topic_draws(p_hop bigint, p_max int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c record; s record; pool bigint[]; draws jsonb := '[]'::jsonb; i int; n_min int := null; bundle jsonb; ps jsonb := '{}'::jsonb; k text;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  for s in select ns.series_id, ns.channel, se.source, se.metric, z.base_level, z.n_obs_90, z.value_kind
           from ripples.att_node_series ns join ripples.att_series se on se.series_id = ns.series_id join ripples.att_zvec z on z.series_id = ns.series_id
           where ns.node = c.node and z.kappa >= 0.3 and not (ns.channel = any(coalesce(c.excluded_ch, '{}'))) loop
    with cand as (
      select z.series_id, z.base_level, z.n_obs_90,
             ntile(10) over (order by z.base_level) dec
      from ripples.att_zvec z join ripples.att_series se on se.series_id = z.series_id
      where se.source = s.source and se.metric = s.metric and se.key <> '__total__' and z.kappa >= 0.3 and z.grain = 'day'),
    me as (select dec from cand where series_id = s.series_id)
    select coalesce(array_agg(cand.series_id order by encode(extensions.digest(cand.series_id::text || p_hop::text, 'sha256'), 'hex')), '{}') into pool
    from cand, me
    where cand.series_id <> s.series_id and cand.dec = me.dec
      and least(cand.n_obs_90, s.n_obs_90)::float8 / greatest(cand.n_obs_90, s.n_obs_90, 1) >= 0.8
      and cand.series_id not in (select ns2.series_id from ripples.att_node_series ns2 where ns2.node = c.node);
    ps := ps || jsonb_build_object(s.series_id::text, jsonb_build_object('channel', s.channel, 'pool', to_jsonb(pool)));
    n_min := least(coalesce(n_min, cardinality(pool)), cardinality(pool));
  end loop;
  if n_min is null or n_min = 0 then return '[]'::jsonb; end if;
  for i in 1..least(n_min, p_max) loop
    bundle := '[]'::jsonb;
    for k in select * from jsonb_object_keys(ps) loop
      bundle := bundle || jsonb_build_object('series_id', (ps -> k -> 'pool' ->> (i - 1))::bigint, 'channel', ps -> k ->> 'channel');
    end loop;
    draws := draws || jsonb_build_array(bundle);
  end loop;
  return draws;
end $$;

-- Real bundle of a hop (series with κ ≥ 0.3, proposing channels excluded)
create or replace function ripples.att_hop_bundle(p_hop bigint) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('series_id', ns.series_id, 'channel', ns.channel) order by ns.series_id), '[]'::jsonb)
  from ripples.att_hop_candidates c join ripples.att_node_series ns on ns.node = c.node
  where c.hop_id = p_hop
$$;

-- ENGINE §10.3: att_test_hop(hop, look, placebo, draw). placebo null → the real statistic; 'date' | 'link' | 'topic' → one draw of that family;
-- 'rival' → the statistic at rival event p_draw's onset (attribution); returns the full statistic jsonb. The look's data end is looks[look] − 1.
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
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x));
  v_tp := c.onset;
  if p_placebo is null then
    res := ripples.att_hop_stat_b(bundle, v_tp, v_end, c.sign, c.excluded_ch, null, agg);
  elsif p_placebo = 'date' then
    dd := ripples.att_date_draws(p_hop_id, greatest(p_draw, 200));
    if p_draw > cardinality(dd) then return null; end if;
    v_tp := dd[p_draw];
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg);
  elsif p_placebo = 'link' then
    ll := ripples.att_link_draws(p_hop_id, 200);
    if p_draw > cardinality(ll) then return null; end if;
    select onset into v_tp from ripples.att_events where event_id = ll[p_draw];
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg);
  elsif p_placebo = 'topic' then
    td := ripples.att_topic_draws(p_hop_id, 300);
    if p_draw > jsonb_array_length(td) then return null; end if;
    perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(td -> (p_draw - 1)) x));
    res := ripples.att_hop_stat_b(td -> (p_draw - 1), v_tp, v_end, c.sign, c.excluded_ch, null, agg);
  elsif p_placebo = 'rival' then
    select onset into v_tp from ripples.att_events where event_id = p_draw;
    res := ripples.att_hop_stat_b(bundle, v_tp, v_tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg);
  else
    raise exception 'att_test_hop: bad placebo %', p_placebo;
  end if;
  return coalesce(res, '{}'::jsonb) || jsonb_build_object('hop_id', p_hop_id, 'look', p_look, 'look_day', v_look, 'tp', v_tp, 'placebo', p_placebo, 'draw', p_draw);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Placebo loop with Besag–Clifford stopping (ENGINE §5.1). Writes counts; the top-100 extension keeps the draw statistics as one
--    compact array row per (hop, look, family) in att_placebo_top (7-day retention) instead of 2,000 rows per hop.
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_placebo_top (
  hop_id bigint not null, look_no smallint not null, kind text not null, as_of date not null,
  t_h real not null, n int not null, exceed int not null, gated boolean not null default true, t_stats real[] not null,
  created_at timestamptz not null default now(), primary key (hop_id, look_no, kind)
);
alter table ripples.att_placebo_top enable row level security;
revoke all on table ripples.att_placebo_top from anon, authenticated, public;

-- p_gate: the real hop passed the pre-trend gate (S_pre < 2), so a draw counts as an exceedance only if it passes the same gate;
-- when the real hop is itself 'already moving' every draw with T′ ≥ T_h counts (ungated), which is the conservative reading.
drop function if exists ripples.att_run_placebos(bigint, text, int, smallint, float8, boolean);
create or replace function ripples.att_run_placebos(p_hop_id bigint, p_family text, p_max int, p_look smallint default 1, p_t float8 default null,
                                                    p_keep_rows boolean default false, p_gate boolean default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); bc int := coalesce((cfg ->> 'bc_stop')::int, 10);
        t_h float8 := p_t; v_end date; bundle jsonb; agg boolean; dd date[]; ll bigint[]; td jsonb; n_draw int; i int; res jsonb; tp date;
        exceed int := 0; n_done int := 0; p float8; gates boolean; stopped boolean := false; tv float8; ids bigint[]; gate boolean := p_gate;
        ts real[] := '{}';
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop_id;
  v_end := c.looks[least(greatest(p_look, 1), cardinality(c.looks))] - 1;
  agg := coalesce(c.path -> 0 -> 'meta' ->> 'demean', '') = 'aggregate';
  bundle := ripples.att_hop_bundle(p_hop_id);
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x));
  if t_h is null or gate is null then
    res := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, null, agg);
    t_h := coalesce(t_h, (res ->> 'T')::float8);
    gate := coalesce(gate, coalesce((res ->> 's_pre')::float8, 0) < 2);
  end if;
  if t_h is null then return jsonb_build_object('family', p_family, 'n', 0, 'p', null, 'reason', 'no statistic'); end if;
  if p_family = 'date' then dd := ripples.att_date_draws(p_hop_id, p_max); n_draw := cardinality(dd);
  elsif p_family = 'link' then ll := ripples.att_link_draws(p_hop_id, p_max); n_draw := cardinality(ll);
  elsif p_family = 'topic' then
    td := ripples.att_topic_draws(p_hop_id, p_max); n_draw := jsonb_array_length(td);
    select array_agg(distinct (x ->> 'series_id')::bigint) into ids from jsonb_array_elements(td) d, jsonb_array_elements(d) x;
    if ids is not null then perform ripples.att_hb_load(ids); end if;
  else raise exception 'att_run_placebos: bad family %', p_family; end if;
  for i in 1..n_draw loop
    if p_family = 'date' then
      tp := dd[i];
      res := ripples.att_hop_stat_b(bundle, tp, tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg);
    elsif p_family = 'link' then
      select onset into tp from ripples.att_events where event_id = ll[i];
      res := ripples.att_hop_stat_b(bundle, tp, tp + (v_end - c.onset), c.sign, c.excluded_ch, null, agg);
    else
      res := ripples.att_hop_stat_b(td -> (i - 1), c.onset, v_end, c.sign, c.excluded_ch, null, agg);
    end if;
    tv := (res ->> 'T')::float8;
    continue when tv is null;
    n_done := n_done + 1;
    gates := (not gate) or coalesce((res ->> 's_pre')::float8, 0) < 2;
    if tv >= t_h and gates then exceed := exceed + 1; end if;
    if p_keep_rows then ts := ts || (case when gates then tv else -tv - 1000 end)::real; end if;   -- gated-out draws stored negative-offset
    if exceed >= bc and not p_keep_rows then stopped := true; exit; end if;
  end loop;
  if p_keep_rows and n_done > 0 then
    insert into ripples.att_placebo_top(hop_id, look_no, kind, as_of, t_h, n, exceed, gated, t_stats)
    values (p_hop_id, p_look, p_family, c.as_of, t_h, n_done, exceed, gate, ts)
    on conflict (hop_id, look_no, kind) do update set t_h = excluded.t_h, n = excluded.n, exceed = excluded.exceed, gated = excluded.gated,
      t_stats = excluded.t_stats, as_of = excluded.as_of, created_at = now();
  end if;
  p := case when n_done = 0 then null when stopped then bc::float8 / n_done else (1 + exceed)::float8 / (1 + n_done) end;
  return jsonb_build_object('family', p_family, 'n', n_done, 'available', n_draw, 'exceed', exceed, 'p', p, 'stopped', stopped, 't_h', t_h, 'gated', gate);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. One look of one hop (att_jobs SQL job: {"rpc":"att_engine_job","args":{"hop_id":..,"look":..}}), writes att_hop_tests
-- ---------------------------------------------------------------------------------------------------------------------
-- reversal check: cross-correlation of Δ(parent READ AR) and Δ(node combined AR proxy: best channel series) over [t_p − 28, t_p + L]
create or replace function ripples.att_lag_reversed(p_hop bigint, p_end date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; pu bigint; pv bigint; zu record; zv record; lagk int; best float8 := null; best_lag int := null;
        t date; a float8; b float8; s float8; n int; lmax int; d0 date; d1 date; iu int; iv int;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  select s.series_id into pu from ripples.att_series s where s.topic_id = c.u_topic and s.source = 'wiki.pv' order by (s.geo = 'en.wikipedia') desc limit 1;
  select ns.series_id into pv from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
    where ns.node = c.node and z.kappa >= 0.3 and z.grain = 'day' order by (ns.channel in ('PHYS','ECON','PM','BLD','CONS','JOBS','INST')) desc, z.kappa desc limit 1;
  if pu is null or pv is null or pu = pv then return jsonb_build_object('checked', false); end if;
  select from_day, n, ar into zu from ripples.att_zvec where series_id = pu and grain = 'day';
  select from_day, n, ar into zv from ripples.att_zvec where series_id = pv and grain = 'day';
  if zu.n is null or zv.n is null then return jsonb_build_object('checked', false); end if;
  lmax := coalesce(c.window_close - c.onset, 7);
  d0 := c.onset - 28; d1 := least(c.onset + lmax, p_end);
  for lagk in -7..lmax loop
    s := 0; n := 0; t := d0 + 1;
    while t <= d1 loop
      iu := (t - lagk - zu.from_day) + 1; iv := (t - zv.from_day) + 1;
      if iu >= 2 and iu <= zu.n and iv >= 2 and iv <= zv.n then
        a := zu.ar[iu] - zu.ar[iu - 1]; b := zv.ar[iv] - zv.ar[iv - 1];
        if a is not null and b is not null then s := s + a * b; n := n + 1; end if;
      end if;
      t := t + 1;
    end loop;
    if n >= 10 and (best is null or s / n > best) then best := s / n; best_lag := lagk; end if;
  end loop;
  return jsonb_build_object('checked', best_lag is not null, 'peak_lag', best_lag, 'reversed', best_lag is not null and best_lag < 0);
end $$;

create or replace function ripples.att_engine_job(p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_hop bigint := (p_args ->> 'hop_id')::bigint; v_look smallint := coalesce((p_args ->> 'look')::smallint, 1);
        c record; ev record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); real_r jsonb; t_h float8; v_end date; v_look_day date;
        pd jsonb; pl jsonb; pt jsonb; p_h float8; n_fam int := 0; fams jsonb := '{}'::jsonb; is_final boolean; link text; att_only boolean;
        cs boolean; rev jsonb; loso boolean := null; src text; r2 jsonb; attrib jsonb; rivals jsonb := '[]'::jsonb; lr_u float8; lr_sum float8; e record;
        agg boolean; bundle jsonb; v_onset date; v_lag int; lag_ok boolean; n_ch3 int; n_out3 int; floor_p float8; flags text[] := '{}';
        min_draws int := coalesce((cfg ->> 'min_family_draws')::int, 30); gate boolean;
begin
  select * into c from ripples.att_hop_candidates where hop_id = v_hop;
  if not found or c.frozen_hash is null then return jsonb_build_object('skipped', 'not frozen'); end if;
  select * into ev from ripples.att_events where event_id = c.event_id;
  if v_look > cardinality(c.looks) then v_look := cardinality(c.looks); end if;
  v_look_day := c.looks[v_look]; v_end := v_look_day - 1; is_final := v_look = cardinality(c.looks);
  agg := coalesce(c.path -> 0 -> 'meta' ->> 'demean', '') = 'aggregate';
  -- MONEY never tests; IO never proposes (no IO candidates exist); waiting_series has no statistic yet
  if exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel = 'MONEY') and
     not exists (select 1 from ripples.att_node_series ns where ns.node = c.node and ns.channel <> 'MONEY') then
    return jsonb_build_object('skipped', 'MONEY channel is disabled');
  end if;
  bundle := ripples.att_hop_bundle(v_hop);
  perform ripples.att_hb_load((select array_agg((x ->> 'series_id')::bigint) from jsonb_array_elements(bundle) x));
  real_r := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, null, agg);
  t_h := (real_r ->> 'T')::float8;
  if t_h is null then
    update ripples.att_hop_candidates set status = 'waiting_series' where hop_id = v_hop and status in ('queued','testing');
    insert into ripples.att_hop_tests(hop_id, look_no, as_of, u_topic, v_topic, t_u, look_day, is_final, tier, tier_reason, s_by_channel, flags)
    values (v_hop, v_look, c.as_of, c.u_topic, c.v_topic, c.onset, v_look_day, is_final, 'watching', 'waiting_series', real_r -> 'channels', array['waiting_series'])
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
  cs := exists (select 1 from ripples.att_common_days d where d.day = coalesce(v_onset, c.onset));
  rev := ripples.att_lag_reversed(v_hop, v_end);
  lag_ok := (v_lag is null or v_lag >= 0) and not coalesce((rev ->> 'reversed')::boolean, false);
  if v_lag is not null and v_lag < 0 then flags := array_append(flags, 'lag_negative'); end if;
  if coalesce((rev ->> 'reversed')::boolean, false) then flags := array_append(flags, 'reversed'); end if;
  if cs then flags := array_append(flags, 'common_shock'); end if;
  if coalesce((real_r ->> 's_pre')::float8, 0) >= 2 then flags := array_append(flags, 'already_moving'); end if;
  if att_only then flags := array_append(flags, 'attention_ripple'); end if;
  if link = 'structural' then flags := array_append(flags, 'linkage_structural'); end if;
  if n_fam < 2 then flags := array_append(flags, 'few_placebo_families'); end if;

  -- LOSO: with ≥ 2 contributing sources, every T_{−s} ≥ 3
  if jsonb_array_length(coalesce(real_r -> 'sources', '[]'::jsonb)) >= 2 then
    loso := true;
    for src in select x from jsonb_array_elements_text(real_r -> 'sources') x loop
      r2 := ripples.att_hop_stat_b(bundle, c.onset, v_end, c.sign, c.excluded_ch, src, agg, false);
      if coalesce((r2 ->> 'T')::float8, 0) < coalesce((cfg ->> 'loso_min_t')::float8, 3) then loso := false; end if;
    end loop;
  end if;

  -- attribution share against concurrent real rivals with a registered path to the same node (ENGINE §3.11)
  lr_u := exp(3 * t_h - 4.5); lr_sum := lr_u;
  for e in select distinct e2.event_id, e2.label, e2.onset from ripples.att_events e2 join ripples.att_hop_candidates c2 on c2.event_id = e2.event_id
            where e2.role = 'real' and e2.event_id <> c.event_id and c2.node = c.node and c2.frozen_hash is not null and not e2.reconstructed
              and abs(e2.onset - c.onset) <= coalesce(c.window_close - c.onset, 7) loop
    r2 := ripples.att_hop_stat_b(bundle, e.onset, e.onset + (v_end - c.onset), c.sign, c.excluded_ch, null, agg, false);
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
  values (v_hop, v_look, c.as_of, c.u_topic, c.v_topic, c.onset, v_onset, v_lag,
          (select jsonb_object_agg(k, v -> 'onset') from jsonb_each(real_r -> 'channels') e(k, v)), t_h, n_ch3, null,
          link, (pt ->> 'p')::real, (pt ->> 'n')::int, (pd ->> 'p')::real, (pd ->> 'n')::int, (pl ->> 'p')::real, (pl ->> 'n')::int, p_h,
          jsonb_build_object('agree', real_r -> 'agree', 'n_out3', n_out3, 'sources', real_r -> 'sources', 'lag_check', rev, 'kappa_min', real_r -> 'kappa_min'),
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
  update ripples.att_hop_candidates set status = 'tested' where hop_id = v_hop;
  return jsonb_build_object('hop_id', v_hop, 'look', v_look, 'T', t_h, 'p', p_h, 'families', n_fam, 'flags', to_jsonb(flags));
end $$;

-- Enqueue every due look of the day into att_jobs (kind 'test', SQL rpc) — dispatched by att_tick('hops') ≤ 40/min (ENGINE §9)
create or replace function ripples.att_engine_enqueue(p_as_of date default current_date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in
    select c.hop_id, c.role, c.voi, l.k as look_no
    from ripples.att_hop_candidates c
    join lateral (select max(o) k from unnest(c.looks) with ordinality u(d, o) where u.d <= p_as_of) l on l.k is not null
    where c.frozen_hash is not null and c.status not in ('skipped') and not c.reconstructed
      and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = l.k and t.t_stat is not null)
    order by (c.role = 'real') desc, c.voi desc nulls last
  loop
    perform ripples.att_job_enqueue('test', null, jsonb_build_object('rpc', 'att_engine_job', 'args', jsonb_build_object('hop_id', r.hop_id, 'look', r.look_no)),
                                    case when r.role = 'real' then 3 else 4 end, 'engtest:' || r.hop_id || ':' || r.look_no, null, now());
    n := n + 1;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'enqueued', n);
end $$;

-- Runner (morning stepper, tests, library mode): run up to p_max due looks now within p_budget_s seconds, real events and high VOI first
drop function if exists ripples.att_engine_run_due(date, int, boolean);
create or replace function ripples.att_engine_run_due(p_as_of date, p_max int default 50, p_reconstructed boolean default false, p_budget_s int default 100000) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; t0 timestamptz := clock_timestamp(); left_over int := 0;
begin
  for r in
    select c.hop_id, l.k as look_no
    from ripples.att_hop_candidates c
    join lateral (select max(o) k from unnest(c.looks) with ordinality u(d, o) where u.d <= p_as_of) l on l.k is not null
    where c.frozen_hash is not null and c.status <> 'skipped' and c.reconstructed = p_reconstructed
      and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = l.k and (t.t_stat is not null or t.tier_reason = 'waiting_series'))
    order by (c.role = 'real') desc, c.voi desc nulls last, c.hop_id limit p_max
  loop
    if clock_timestamp() - t0 > make_interval(secs => p_budget_s) then left_over := left_over + 1; continue; end if;
    perform ripples.att_engine_job(jsonb_build_object('hop_id', r.hop_id, 'look', r.look_no));
    n := n + 1;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'ran', n, 'left_over', left_over, 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- Morning stepper (cron att-engine-tick, every minute 07:35–08:18): ≤ 40 looks per minute (ENGINE §9), one stepper at a time
create or replace function ripples.att_engine_tick_locked(p_as_of date default current_date, p_max int default 40, p_budget_s int default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not pg_try_advisory_lock(hashtext('ripples.att_engine_tick')) then return jsonb_build_object('skipped', 'another stepper holds the lock'); end if;
  begin
    r := ripples.att_engine_run_due(p_as_of, p_max, false, p_budget_s);
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_engine_tick'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_engine_tick'));
  return r;
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
