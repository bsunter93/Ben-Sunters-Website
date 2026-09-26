-- att_ce (WS-G, 2026-09-26): second independent estimator (BigQuery AI.CAUSAL_EFFECT) + Wikipedia BigQuery backfill.
-- Applied to Supabase project kffkasnzqcddpystszch as migration `att_ce_bq_estimator`. Idempotent: safe to re-run.
--
-- OWNER_DECISIONS D-12: "Measured requires agreement: effect sign matches, and the interval excludes 0 at the
-- pre-registered horizon." This file stores the BigQuery results and exposes that rule as a read-time hook. It does not
-- modify any WS-B engine object.
--
-- Objects (all service-only; nothing is granted to anon/authenticated):
--   ripples.att_ce_results           one row per (hop, series, model_version): effect, interval, p_value
--   ripples.att_ce_runs              run log for both GitHub Actions (dry-run bytes, billed bytes, counts)
--   ripples.att_ce_hops_to_eval()    work list for ripples-causal-effect.yml (series embedded, relative day offsets)
--   ripples.att_ce_ingest()          write-back of AI.CAUSAL_EFFECT results
--   ripples.att_ce_log_run()         run log upsert
--   ripples.att_ce_wiki_targets()    work list for ripples-wiki-bq-backfill.yml (registry titles with a history gap)
--   ripples.att_ce_hop_verdict       view: per hop agree | disagree | pending
--   ripples.att_ce_measured_ok()     HOOK: true = CE agrees, false = CE disagrees, null = not evaluated yet
--   ripples.att_ce_gate()            HOOK: engine tier in -> gated tier + reason out (what publish must call)
--   ripples.rm_ce_hop()              "vs forecast (range)" block for a hop card (publish-side, service-only)
--   ripples.att_ce_calibration       view: decoy false-positive rate, control hit rates
--   public.att_ce_*                  thin SECURITY DEFINER wrappers for PostgREST, EXECUTE to service_role only
--
-- Config: ripples.att_config key 'ce' (see the insert below). gate_mode: 'enforce' | 'shadow' | 'off'.
--
-- HOW WS-F WIRES IT (publish / payload build; do not change WS-B's stored tier):
--   select ripples.att_ce_gate(hop_id, tier)  -> {"tier":"measured"|"likely"|..., "reason":text|null, "ce":{...}}
--   Use ->>'tier' as the published tier, and when it differs from the engine tier put ->>'reason' in tier_reason
--   ("forecast check pending" / "forecast check disagrees"). Show ripples.rm_ce_hop(hop_id) as "vs forecast (range)";
--   never show p_value as a "probability of causal effect" (D-12 wording rule).
--   Acceptance (ENGINE_SPEC §12) should also read ripples.att_ce_calibration: decoy_sig_rate is the CE decoy FPR.

-- 1. config -------------------------------------------------------------------------------------------------------------
insert into ripples.att_config(key, value) values ('ce', $j${
  "model_version": "ce-arima-1",
  "pre_days": 120,
  "min_pre_cov": 0.8,
  "min_post_cov": 0.8,
  "max_horizon_days": 120,
  "confidence": 0.95,
  "gate_mode": "enforce",
  "retry_failed_days": 7,
  "wiki_bq_days": 420
}$j$::jsonb)
on conflict (key) do nothing;

-- 2. tables -------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_ce_runs (
  run_id          bigserial primary key,
  kind            text not null check (kind in ('causal_effect', 'wiki_bq_backfill')),
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          text not null default 'running' check (status in ('running', 'ok', 'aborted', 'failed')),
  dry_run_bytes   bigint,
  billed_bytes    bigint,
  units           int,
  rows_written    int,
  gh_run          text,
  detail          jsonb not null default '{}'::jsonb
);

create table if not exists ripples.att_ce_results (
  hop_id          bigint not null,
  series_id       bigint not null,
  model_version   text   not null,
  horizon_days    smallint not null,
  onset           date   not null,
  pre_days        smallint,
  n_pre           int,
  n_post          int,
  role            text,              -- snapshot of att_hop_candidates.role at ingest
  engine_tier     text,              -- snapshot of the engine's latest tier at ingest
  exp_sign        smallint,          -- engine direction: hop sign, else sign of ln(rho)
  abs_effect      double precision,  -- SUM(actual - expected) over the horizon
  rel_effect      double precision,  -- SUM(actual - expected) / SUM(expected)
  abs_lo          double precision,  -- A - SUM(upper_bound)
  abs_hi          double precision,  -- A - SUM(lower_bound)
  rel_lo          double precision,  -- (A - U) / U
  rel_hi          double precision,  -- (A - L) / L; null when L <= 0 (unbounded above)
  p_value         double precision,  -- stored for calibration only; never displayed as a probability of cause
  confidence      real,
  status          text not null default 'ok',  -- 'ok' or the AI.CAUSAL_EFFECT status / script error
  as_of           date not null,
  run_id          bigint references ripples.att_ce_runs(run_id) on delete set null,
  evaluated_at    timestamptz not null default now(),
  detail          jsonb not null default '{}'::jsonb,
  primary key (hop_id, series_id, model_version)
);
create index if not exists att_ce_results_hop on ripples.att_ce_results(hop_id);

alter table ripples.att_ce_runs    enable row level security;
alter table ripples.att_ce_results enable row level security;
revoke all on ripples.att_ce_runs, ripples.att_ce_results from anon, authenticated, public;
revoke all on sequence ripples.att_ce_runs_run_id_seq from anon, authenticated, public;

-- 3. work list for the causal-effect Action ------------------------------------------------------------------------------
-- Units = (hop, series of the hop's node). Real hops whose latest engine tier is likely|measured, all positive/negative
-- control hops, and a deterministic daily sample of decoy (placebo) hops. Only hops whose pre-registered window has
-- closed. Each unit carries its series as day offsets from the hop onset (t) and values (y), pre + post window, so the
-- Action can align every unit on one intervention timestamp and group by horizon.
create or replace function ripples.att_ce_hops_to_eval(p_as_of date default null, p_max_units int default 400,
                                                      p_decoy_sample int default 120, p_pre_days int default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  cfg     jsonb := coalesce(ripples._att_cfg('ce'), '{}'::jsonb);
  v_as    date  := coalesce(p_as_of, (now() at time zone 'utc')::date);
  v_pre   int   := least(greatest(coalesce(p_pre_days, (cfg->>'pre_days')::int, 120), 28), 365);
  v_model text  := coalesce(cfg->>'model_version', 'ce-arima-1');
  v_cpre  real  := coalesce((cfg->>'min_pre_cov')::real, 0.8);
  v_cpost real  := coalesce((cfg->>'min_post_cov')::real, 0.8);
  v_maxh  int   := coalesce((cfg->>'max_horizon_days')::int, 120);
  v_retry int   := coalesce((cfg->>'retry_failed_days')::int, 7);
  v_units jsonb;
begin
  with lt as (
    select distinct on (t.hop_id) t.hop_id, t.tier, coalesce(t.rho_shrunk, t.rho_raw) as rho
    from ripples.att_hop_tests t
    order by t.hop_id, t.look_no desc, t.as_of desc),
  hop as (
    select c.hop_id, c.role, c.node, c.onset, c.window_close, lt.tier,
           (case when coalesce(c.sign, 0) <> 0 then sign(c.sign)
                 when lt.rho > 1 then 1 when lt.rho < 1 then -1 else 0 end)::smallint as exp_sign,
           (c.window_close - c.onset + 1) as horizon,
           case c.role when 'real' then 0 when 'positive_control' then 1 when 'negative_control' then 2 else 3 end as prio,
           md5(c.hop_id::text || '|' || v_as::text) as rk
    from ripples.att_hop_candidates c left join lt on lt.hop_id = c.hop_id
    where c.onset is not null and c.window_close is not null and c.window_close >= c.onset
      and c.window_close - c.onset + 1 <= v_maxh and c.window_close < v_as
      and ((c.role = 'real' and lt.tier in ('likely', 'measured'))
           or c.role in ('positive_control', 'negative_control', 'decoy'))),
  u as (
    select h.*, ns.series_id, ns.channel
    from hop h join ripples.att_node_series ns on ns.node = h.node
    where not exists (select 1 from ripples.att_ce_results r
                      where r.hop_id = h.hop_id and r.series_id = ns.series_id and r.model_version = v_model
                        and r.horizon_days = h.horizon
                        and (r.status = 'ok' or r.evaluated_at > now() - make_interval(days => v_retry)))),
  dh as (
    select d.hop_id from (select distinct u.hop_id, u.rk from u where u.role = 'decoy') d
    order by d.rk limit greatest(coalesce(p_decoy_sample, 0), 0)),
  u2 as (select u.* from u where u.role <> 'decoy' or u.hop_id in (select dh.hop_id from dh)),
  uo as (
    select u2.*, x.t, x.y, x.n_pre, x.n_post
    from u2 cross join lateral (
      select array_agg(o.day - u2.onset order by o.day) as t,
             array_agg(o.value order by o.day) as y,
             count(*) filter (where o.day < u2.onset) as n_pre,
             count(*) filter (where o.day >= u2.onset) as n_post
      from ripples.attention_obs o
      where o.series_id = u2.series_id and o.day between u2.onset - v_pre and u2.window_close) x),
  sel as (
    select * from uo
    where uo.n_pre >= v_cpre * v_pre and uo.n_post >= v_cpost * uo.horizon
    order by uo.prio, uo.rk, uo.series_id
    limit greatest(coalesce(p_max_units, 400), 0))
  select coalesce(jsonb_agg(jsonb_build_object(
           'unit_id', 'h' || s.hop_id || '_s' || s.series_id, 'hop_id', s.hop_id, 'series_id', s.series_id,
           'channel', s.channel, 'role', s.role, 'tier', s.tier, 'exp_sign', s.exp_sign,
           'onset', s.onset, 'horizon', s.horizon, 'n_pre', s.n_pre, 'n_post', s.n_post,
           't', to_jsonb(s.t), 'y', to_jsonb(s.y)) order by s.prio, s.rk, s.series_id), '[]'::jsonb)
    into v_units
  from sel s;

  return jsonb_build_object('as_of', v_as, 'model_version', v_model, 'pre_days', v_pre,
                            'confidence', coalesce((cfg->>'confidence')::real, 0.95), 'units', v_units);
end $$;

-- 4. run log ------------------------------------------------------------------------------------------------------------
-- p: {run_id?, kind, status?, dry_run_bytes?, billed_bytes?, units?, rows_written?, gh_run?, detail?}. Returns run_id.
create or replace function ripples.att_ce_log_run(p jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if p ? 'run_id' and (p->>'run_id') ~ '^\d+$' then
    update ripples.att_ce_runs r set
      status        = coalesce(p->>'status', r.status),
      finished_at   = case when coalesce(p->>'status', r.status) <> 'running' then now() else r.finished_at end,
      dry_run_bytes = coalesce((p->>'dry_run_bytes')::bigint, r.dry_run_bytes),
      billed_bytes  = coalesce((p->>'billed_bytes')::bigint, r.billed_bytes),
      units         = coalesce((p->>'units')::int, r.units),
      rows_written  = coalesce((p->>'rows_written')::int, r.rows_written),
      detail        = r.detail || coalesce(case when jsonb_typeof(p->'detail') = 'object' then p->'detail' end, '{}'::jsonb)
    where r.run_id = (p->>'run_id')::bigint
    returning r.run_id into v_id;
    return v_id;
  end if;
  insert into ripples.att_ce_runs(kind, status, dry_run_bytes, billed_bytes, units, rows_written, gh_run, detail)
  values (p->>'kind', coalesce(p->>'status', 'running'), (p->>'dry_run_bytes')::bigint, (p->>'billed_bytes')::bigint,
          (p->>'units')::int, (p->>'rows_written')::int, left(p->>'gh_run', 200),
          coalesce(case when jsonb_typeof(p->'detail') = 'object' then p->'detail' end, '{}'::jsonb))
  returning run_id into v_id;
  -- keep the log small
  delete from ripples.att_ce_runs where started_at < now() - interval '180 days';
  return v_id;
end $$;

-- 5. ingest -------------------------------------------------------------------------------------------------------------
-- p_run: {run_id?, as_of?}. p_rows: [{hop_id, series_id, model_version, horizon_days, onset, pre_days, n_pre, n_post,
-- abs_effect, rel_effect, abs_lo, abs_hi, rel_lo, rel_hi, p_value, confidence, status, detail}].
-- Rejects rows whose series is not in the hop's bundle or whose horizon is not the pre-registered one.
create or replace function ripples.att_ce_ingest(p_run jsonb, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_n int := 0; v_rej jsonb; v_as date; v_run bigint;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows', 0, 'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'p_rows must be a JSON array')));
  end if;
  v_as  := case when p_run->>'as_of' ~ '^\d{4}-\d{2}-\d{2}$' then (p_run->>'as_of')::date else (now() at time zone 'utc')::date end;
  v_run := case when p_run->>'run_id' ~ '^\d+$' then (p_run->>'run_id')::bigint end;
  if v_run is not null and not exists (select 1 from ripples.att_ce_runs r where r.run_id = v_run) then v_run := null; end if;

  drop table if exists pg_temp._ce_in;
  create temp table _ce_in on commit drop as
  select (e.ord - 1)::int as i,
         case when e.r->>'hop_id' ~ '^\d+$' then (e.r->>'hop_id')::bigint end as hop_id,
         case when e.r->>'series_id' ~ '^\d+$' then (e.r->>'series_id')::bigint end as series_id,
         nullif(e.r->>'model_version', '') as model_version,
         case when e.r->>'horizon_days' ~ '^\d+$' then (e.r->>'horizon_days')::int end as horizon_days,
         case when e.r->>'pre_days' ~ '^\d+$' then (e.r->>'pre_days')::int end as pre_days,
         case when e.r->>'n_pre' ~ '^\d+$' then (e.r->>'n_pre')::int end as n_pre,
         case when e.r->>'n_post' ~ '^\d+$' then (e.r->>'n_post')::int end as n_post,
         case when jsonb_typeof(e.r->'abs_effect') = 'number' then (e.r->>'abs_effect')::float8 end as abs_effect,
         case when jsonb_typeof(e.r->'rel_effect') = 'number' then (e.r->>'rel_effect')::float8 end as rel_effect,
         case when jsonb_typeof(e.r->'abs_lo') = 'number' then (e.r->>'abs_lo')::float8 end as abs_lo,
         case when jsonb_typeof(e.r->'abs_hi') = 'number' then (e.r->>'abs_hi')::float8 end as abs_hi,
         case when jsonb_typeof(e.r->'rel_lo') = 'number' then (e.r->>'rel_lo')::float8 end as rel_lo,
         case when jsonb_typeof(e.r->'rel_hi') = 'number' then (e.r->>'rel_hi')::float8 end as rel_hi,
         case when jsonb_typeof(e.r->'p_value') = 'number' then (e.r->>'p_value')::float8 end as p_value,
         case when jsonb_typeof(e.r->'confidence') = 'number' then (e.r->>'confidence')::real end as confidence,
         coalesce(nullif(left(e.r->>'status', 500), ''), 'ok') as status,
         case when jsonb_typeof(e.r->'detail') = 'object' then e.r->'detail' else '{}'::jsonb end as detail,
         null::text as reason
  from jsonb_array_elements(p_rows) with ordinality e(r, ord);

  update pg_temp._ce_in set reason = 'missing_ids' where hop_id is null or series_id is null or model_version is null or horizon_days is null;
  update pg_temp._ce_in i set reason = 'series_not_in_hop'
   where i.reason is null and not exists (
     select 1 from ripples.att_hop_candidates c join ripples.att_node_series ns on ns.node = c.node
     where c.hop_id = i.hop_id and ns.series_id = i.series_id);
  update pg_temp._ce_in i set reason = 'horizon_not_preregistered'
   where i.reason is null and not exists (
     select 1 from ripples.att_hop_candidates c
     where c.hop_id = i.hop_id and c.window_close - c.onset + 1 = i.horizon_days);
  update pg_temp._ce_in i set reason = 'ok_without_effect'
   where i.reason is null and i.status = 'ok' and (i.abs_effect is null or i.abs_lo is null or i.abs_hi is null);
  update pg_temp._ce_in i set reason = 'bad_interval'
   where i.reason is null and i.status = 'ok' and i.abs_lo > i.abs_hi;

  with lt as (
    select distinct on (t.hop_id) t.hop_id, t.tier, coalesce(t.rho_shrunk, t.rho_raw) as rho
    from ripples.att_hop_tests t where t.hop_id in (select hop_id from pg_temp._ce_in where reason is null)
    order by t.hop_id, t.look_no desc, t.as_of desc),
  src as (
    select distinct on (i.hop_id, i.series_id, i.model_version) i.*, c.onset, c.role, lt.tier,
           (case when coalesce(c.sign, 0) <> 0 then sign(c.sign) when lt.rho > 1 then 1 when lt.rho < 1 then -1 else 0 end)::smallint as exp_sign
    from pg_temp._ce_in i join ripples.att_hop_candidates c on c.hop_id = i.hop_id left join lt on lt.hop_id = i.hop_id
    where i.reason is null
    order by i.hop_id, i.series_id, i.model_version, i.i desc),
  up as (
    insert into ripples.att_ce_results as r (hop_id, series_id, model_version, horizon_days, onset, pre_days, n_pre, n_post,
      role, engine_tier, exp_sign, abs_effect, rel_effect, abs_lo, abs_hi, rel_lo, rel_hi, p_value, confidence, status,
      as_of, run_id, evaluated_at, detail)
    select s.hop_id, s.series_id, s.model_version, s.horizon_days, s.onset, s.pre_days, s.n_pre, s.n_post,
           s.role, s.tier, s.exp_sign, s.abs_effect, s.rel_effect, s.abs_lo, s.abs_hi, s.rel_lo, s.rel_hi, s.p_value,
           s.confidence, s.status, v_as, v_run, now(), s.detail
    from src s
    on conflict (hop_id, series_id, model_version) do update set
      horizon_days = excluded.horizon_days, onset = excluded.onset, pre_days = excluded.pre_days,
      n_pre = excluded.n_pre, n_post = excluded.n_post, role = excluded.role, engine_tier = excluded.engine_tier,
      exp_sign = excluded.exp_sign, abs_effect = excluded.abs_effect, rel_effect = excluded.rel_effect,
      abs_lo = excluded.abs_lo, abs_hi = excluded.abs_hi, rel_lo = excluded.rel_lo, rel_hi = excluded.rel_hi,
      p_value = excluded.p_value, confidence = excluded.confidence, status = excluded.status, as_of = excluded.as_of,
      run_id = excluded.run_id, evaluated_at = excluded.evaluated_at, detail = excluded.detail
    returning 1)
  select count(*) into v_n from up;

  select coalesce(jsonb_agg(jsonb_build_object('i', i, 'reason', reason) order by i), '[]'::jsonb) into v_rej
  from (select i, reason from pg_temp._ce_in where reason is not null order by i limit 200) x;
  drop table if exists pg_temp._ce_in;
  return jsonb_build_object('rows', v_n, 'rejected', v_rej);
end $$;

-- 6. agreement rule (D-12) ------------------------------------------------------------------------------------------------
-- Per series: agree  = engine direction e <> 0, sign(abs_effect) = e, and the interval excludes 0 on that side
--                      (e > 0: abs_lo > 0; e < 0: abs_hi < 0), at the pre-registered horizon (enforced at ingest).
--             oppose = interval excludes 0 on the other side.
-- Per hop:    agree when >= 1 series agrees and none opposes; disagree when evaluated otherwise; pending when no
--             'ok' result exists for the current model_version.
create or replace view ripples.att_ce_hop_verdict with (security_invoker = true) as
with cfg as (select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv),
r as (
  select r.*,
         (r.exp_sign <> 0 and sign(r.abs_effect) = r.exp_sign
          and ((r.exp_sign > 0 and r.abs_lo > 0) or (r.exp_sign < 0 and r.abs_hi < 0))) as agree,
         ((r.exp_sign > 0 and r.abs_hi < 0) or (r.exp_sign < 0 and r.abs_lo > 0)) as oppose,
         (r.abs_lo > 0 or r.abs_hi < 0) as sig
  from ripples.att_ce_results r, cfg
  where r.model_version = cfg.mv and r.status = 'ok')
select r.hop_id,
       case when bool_or(r.agree) and not bool_or(r.oppose) then 'agree' else 'disagree' end as state,
       count(*)::int as n_series, count(*) filter (where r.agree)::int as n_agree,
       count(*) filter (where r.oppose)::int as n_oppose, bool_or(r.sig) as any_sig,
       max(r.exp_sign) as exp_sign, max(r.horizon_days) as horizon_days, max(r.evaluated_at) as evaluated_at,
       min(r.role) as role
from r group by r.hop_id;

-- HOOK 1: boolean. true = CE agrees; false = evaluated and does not agree; null = not evaluated (pending).
create or replace function ripples.att_ce_measured_ok(p_hop bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select case v.state when 'agree' then true when 'disagree' then false end
  from ripples.att_ce_hop_verdict v where v.hop_id = p_hop
$$;

-- HOOK 2: the gate. Engine tier in, published tier out. Only 'measured' is ever changed (to 'likely').
-- gate_mode 'enforce' (default, D-12) demotes pending and disagreeing hops; 'shadow' reports but never demotes;
-- 'off' passes through.
create or replace function ripples.att_ce_gate(p_hop bigint, p_tier text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_mode text := coalesce(ripples._att_cfg('ce')->>'gate_mode', 'enforce');
  v ripples.att_ce_hop_verdict%rowtype;
  v_state text; v_tier text := p_tier; v_reason text;
begin
  select * into v from ripples.att_ce_hop_verdict x where x.hop_id = p_hop;
  v_state := coalesce(v.state, 'pending');
  if p_tier = 'measured' and v_mode = 'enforce' and v_state <> 'agree' then
    v_tier := 'likely';
    v_reason := case v_state when 'pending' then 'forecast check pending' else 'forecast check disagrees' end;
  end if;
  return jsonb_build_object('tier', v_tier, 'engine_tier', p_tier, 'reason', v_reason, 'mode', v_mode,
    'ce', jsonb_build_object('state', v_state, 'n_series', v.n_series, 'n_agree', v.n_agree, 'n_oppose', v.n_oppose,
                             'horizon_days', v.horizon_days, 'evaluated_at', v.evaluated_at));
end $$;

-- Card block: "vs forecast (range)". Representative series = an agreeing series (smallest p), else smallest p.
-- rel/lo/hi are relative effects over the pre-registered horizon (0.12 = 12% above forecast).
create or replace function ripples.rm_ce_hop(p_hop bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  with cfg as (select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv),
  r as (
    select r.*, (r.exp_sign <> 0 and sign(r.abs_effect) = r.exp_sign
                 and ((r.exp_sign > 0 and r.abs_lo > 0) or (r.exp_sign < 0 and r.abs_hi < 0))) as agree
    from ripples.att_ce_results r, cfg
    where r.hop_id = p_hop and r.model_version = cfg.mv and r.status = 'ok')
  select jsonb_build_object('label', 'vs forecast (range)', 'series_id', r.series_id,
           'rel', round(r.rel_effect::numeric, 4), 'lo', round(r.rel_lo::numeric, 4), 'hi', round(r.rel_hi::numeric, 4),
           'confidence', r.confidence, 'horizon_days', r.horizon_days, 'from', r.onset,
           'to', r.onset + r.horizon_days - 1, 'agrees', r.agree, 'method', 'BigQuery AI.CAUSAL_EFFECT (ARIMA_PLUS forecast)',
           'model_version', r.model_version)
  from r order by r.agree desc, r.p_value nulls last, r.series_id limit 1
$$;

-- Calibration (D-12: "calibrated first on the placebo events and the positive/negative controls; its decoy
-- false-positive rate is reported"). sig = interval excludes 0 in either direction.
create or replace view ripples.att_ce_calibration with (security_invoker = true) as
with cfg as (select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv),
v as (select * from ripples.att_ce_hop_verdict)
select c.role,
       count(*)::int as hops_evaluated,
       count(*) filter (where v.any_sig)::int as hops_sig,
       round((count(*) filter (where v.any_sig))::numeric / nullif(count(*), 0), 4) as sig_rate,
       count(*) filter (where v.state = 'agree')::int as hops_agree,
       round((count(*) filter (where v.state = 'agree'))::numeric / nullif(count(*), 0), 4) as agree_rate,
       (select mv from cfg) as model_version,
       max(v.evaluated_at) as last_evaluated
from v join ripples.att_hop_candidates c on c.hop_id = v.hop_id
group by c.role;
-- decoy row: sig_rate = CE decoy false-positive rate; positive_control row: agree_rate = hit rate;
-- negative_control row: sig_rate should sit inside the decoy rate's interval.

-- 7. wiki BigQuery backfill work list -------------------------------------------------------------------------------------
-- Registry wiki.pv titles (ripples._att_wiki_reg: active topics + panel) with a history gap at the start of
-- [p_from, p_to]. fill_to = day before the series' first stored day in range (or p_to when none), so AQS rows are never
-- overwritten; the backfill only extends history backwards. Also returns DB headroom for the per-run cap.
create or replace function ripples.att_ce_wiki_targets(p_from date default null, p_to date default null, p_limit int default 1000)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  cfg    jsonb := coalesce(ripples._att_cfg('ce'), '{}'::jsonb);
  v_to   date  := coalesce(p_to, (now() at time zone 'utc')::date - 2);
  v_from date  := coalesce(p_from, v_to - coalesce((cfg->>'wiki_bq_days')::int, 420));
  v_t    jsonb;
begin
  if v_from < date '2015-05-01' then v_from := date '2015-05-01'; end if;
  with reg as (select distinct r.key, r.geo, r.act from ripples._att_wiki_reg() r where r.geo like '%.wikipedia'),
  s as (
    select g.key, g.geo, g.act, sr.series_id,
           (select min(o.day) from ripples.attention_obs o
             where o.series_id = sr.series_id and o.day between v_from and v_to) as first_in
    from reg g
    left join ripples.att_series sr on sr.source = 'wiki.pv' and sr.metric = 'n' and sr.geo = g.geo and sr.key = g.key),
  t as (
    select s.*, v_from as fill_from, coalesce(s.first_in - 1, v_to) as fill_to from s)
  select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'geo', t.geo, 'series_id', t.series_id,
                                               'fill_from', t.fill_from, 'fill_to', t.fill_to)
                            order by t.act desc, (t.fill_to - t.fill_from) desc, t.key), '[]'::jsonb)
    into v_t
  from (select * from t where t.fill_to >= t.fill_from
        order by t.act desc, (t.fill_to - t.fill_from) desc, t.key limit greatest(coalesce(p_limit, 1000), 0)) t;

  return jsonb_build_object('from', v_from, 'to', v_to,
    'db_mb', round(pg_database_size(current_database()) / 1048576.0),
    'cap_mb', coalesce((ripples._att_cfg('db_cap_mb'))::text::numeric, 400),
    'targets', v_t);
end $$;

-- 8. PostgREST wrappers (service_role only) -----------------------------------------------------------------------------
create or replace function public.att_ce_hops_to_eval(p_as_of date default null, p_max_units int default 400,
                                                      p_decoy_sample int default 120, p_pre_days int default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select ripples.att_ce_hops_to_eval(p_as_of, p_max_units, p_decoy_sample, p_pre_days) $$;
create or replace function public.att_ce_ingest(p_run jsonb, p_rows jsonb)
returns jsonb language sql security definer set search_path = '' as $$ select ripples.att_ce_ingest(p_run, p_rows) $$;
create or replace function public.att_ce_log_run(p jsonb)
returns bigint language sql security definer set search_path = '' as $$ select ripples.att_ce_log_run(p) $$;
create or replace function public.att_ce_wiki_targets(p_from date default null, p_to date default null, p_limit int default 1000)
returns jsonb language sql stable security definer set search_path = '' as $$
  select ripples.att_ce_wiki_targets(p_from, p_to, p_limit) $$;

do $$ declare f text; begin
  foreach f in array array[
    'ripples.att_ce_hops_to_eval(date, int, int, int)', 'ripples.att_ce_log_run(jsonb)', 'ripples.att_ce_ingest(jsonb, jsonb)',
    'ripples.att_ce_measured_ok(bigint)', 'ripples.att_ce_gate(bigint, text)', 'ripples.rm_ce_hop(bigint)',
    'ripples.att_ce_wiki_targets(date, date, int)',
    'public.att_ce_hops_to_eval(date, int, int, int)', 'public.att_ce_ingest(jsonb, jsonb)', 'public.att_ce_log_run(jsonb)',
    'public.att_ce_wiki_targets(date, date, int)'] loop
    execute format('revoke all on function %s from anon, authenticated, public', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke all on ripples.att_ce_hop_verdict, ripples.att_ce_calibration from anon, authenticated, public;
grant select on ripples.att_ce_hop_verdict, ripples.att_ce_calibration, ripples.att_ce_results, ripples.att_ce_runs to service_role;
