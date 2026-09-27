-- Forecast-check eligibility (applied after the first live run, 2026-09-26).
-- First run: decoys "significant" 51/81, almost all from
--   * fema.decl (zero-inflated counts): forecast interval collapses to [0,0] -> any
--     declaration is "significant" (43/49 decoys);
--   * 91-day horizons fitted on 120 pre-days: ARIMA cannot learn annual seasonality
--     (iem.warn 8/17 decoys).
-- Rule: a series result counts only if its summed forecast interval has positive width
-- and horizon_days <= ce.max_horizon (default 29). A hop with no eligible series is
-- 'ineligible' and cannot be Measured (conservative: no second opinion, no Measured).

create or replace view ripples.att_ce_hop_verdict as
with cfg as (
  select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv,
         coalesce((ripples._att_cfg('ce')->>'max_horizon')::int, 29) as max_h
), r0 as (
  select r.*,
         (coalesce((r.detail->>'sum_upper')::float8 - (r.detail->>'sum_lower')::float8, r.abs_hi - r.abs_lo) > 0
          and r.horizon_days <= cfg.max_h) as eligible
  from ripples.att_ce_results r, cfg
  where r.model_version = cfg.mv and r.status = 'ok'
), r as (
  select r0.*,
    r0.eligible and r0.exp_sign <> 0 and sign(r0.abs_effect) = r0.exp_sign::float8
      and ((r0.exp_sign > 0 and r0.abs_lo > 0) or (r0.exp_sign < 0 and r0.abs_hi < 0)) as agree,
    r0.eligible and ((r0.exp_sign > 0 and r0.abs_hi < 0) or (r0.exp_sign < 0 and r0.abs_lo > 0)) as oppose,
    r0.eligible and (r0.abs_lo > 0 or r0.abs_hi < 0) as sig
  from r0
)
select hop_id,
  case when not bool_or(eligible) then 'ineligible'
       when bool_or(agree) and not bool_or(oppose) then 'agree'
       else 'disagree' end as state,
  count(*)::int as n_series,
  count(*) filter (where agree)::int as n_agree,
  count(*) filter (where oppose)::int as n_oppose,
  bool_or(sig) as any_sig,
  max(exp_sign) as exp_sign,
  max(horizon_days) as horizon_days,
  max(evaluated_at) as evaluated_at,
  min(role) as role,
  count(*) filter (where eligible)::int as n_eligible
from r group by hop_id;

create or replace view ripples.att_ce_calibration as
with cfg as (select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv),
v as (select * from ripples.att_ce_hop_verdict where state <> 'ineligible')
select c.role,
  count(*)::int as hops_evaluated,
  count(*) filter (where v.any_sig)::int as hops_sig,
  round(count(*) filter (where v.any_sig)::numeric / nullif(count(*), 0), 4) as sig_rate,
  count(*) filter (where v.state = 'agree')::int as hops_agree,
  round(count(*) filter (where v.state = 'agree')::numeric / nullif(count(*), 0), 4) as agree_rate,
  (select mv from cfg) as model_version,
  max(v.evaluated_at) as last_evaluated
from v join ripples.att_hop_candidates c on c.hop_id = v.hop_id
group by c.role;

revoke all on ripples.att_ce_hop_verdict, ripples.att_ce_calibration from anon, authenticated;

create or replace function ripples.att_ce_gate(p_hop bigint, p_tier text)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_mode text := coalesce(ripples._att_cfg('ce')->>'gate_mode', 'enforce');
  v ripples.att_ce_hop_verdict%rowtype;
  v_state text; v_tier text := p_tier; v_reason text;
begin
  select * into v from ripples.att_ce_hop_verdict x where x.hop_id = p_hop;
  v_state := coalesce(v.state, 'pending');
  if p_tier = 'measured' and v_mode = 'enforce' and v_state <> 'agree' then
    v_tier := 'likely';
    v_reason := case v_state when 'pending' then 'forecast check pending'
                             when 'ineligible' then 'forecast check cannot assess this series'
                             else 'forecast check disagrees' end;
  end if;
  return jsonb_build_object('tier', v_tier, 'engine_tier', p_tier, 'reason', v_reason, 'mode', v_mode,
    'ce', jsonb_build_object('state', v_state, 'n_series', v.n_series, 'n_eligible', v.n_eligible,
                             'n_agree', v.n_agree, 'n_oppose', v.n_oppose,
                             'horizon_days', v.horizon_days, 'evaluated_at', v.evaluated_at));
end $function$;

create or replace function ripples.att_ce_measured_ok(p_hop bigint)
returns boolean language sql stable security definer set search_path to '' as $function$
  select case v.state when 'agree' then true when 'disagree' then false when 'ineligible' then false end
  from ripples.att_ce_hop_verdict v where v.hop_id = p_hop
$function$;

create or replace function ripples.rm_ce_hop(p_hop bigint)
returns jsonb language sql stable security definer set search_path to '' as $function$
  with cfg as (select coalesce(ripples._att_cfg('ce')->>'model_version', 'ce-arima-1') as mv,
                      coalesce((ripples._att_cfg('ce')->>'max_horizon')::int, 29) as max_h),
  r as (
    select r.*,
      (coalesce((r.detail->>'sum_upper')::float8 - (r.detail->>'sum_lower')::float8, r.abs_hi - r.abs_lo) > 0
        and r.horizon_days <= cfg.max_h) as eligible
    from ripples.att_ce_results r, cfg
    where r.hop_id = p_hop and r.model_version = cfg.mv and r.status = 'ok'),
  r2 as (
    select r.*, r.eligible and r.exp_sign <> 0 and sign(r.abs_effect) = r.exp_sign
                 and ((r.exp_sign > 0 and r.abs_lo > 0) or (r.exp_sign < 0 and r.abs_hi < 0)) as agree
    from r where r.eligible)
  select jsonb_build_object('label', 'vs forecast (range)', 'series_id', r2.series_id,
           'rel', round(r2.rel_effect::numeric, 4), 'lo', round(r2.rel_lo::numeric, 4), 'hi', round(r2.rel_hi::numeric, 4),
           'confidence', r2.confidence, 'horizon_days', r2.horizon_days, 'from', r2.onset,
           'to', r2.onset + r2.horizon_days - 1, 'agrees', r2.agree, 'method', 'BigQuery AI.CAUSAL_EFFECT (ARIMA_PLUS forecast)',
           'model_version', r2.model_version)
  from r2 order by r2.agree desc, r2.p_value nulls last, r2.series_id limit 1
$function$;

update ripples.att_config set value = value || '{"max_horizon": 29}'::jsonb where key = 'ce';
