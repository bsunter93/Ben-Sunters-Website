-- 17b_att_social_jet_cron_gate (W7 att-social, 2026-09-25, applied as migration att_social_jet_cron_gate)
-- Supersedes the catch-up cron command written by 17_att_social_fixes4 (its defer_until check is dropped: the edge
-- code is unchanged, still v2026-09-25.s4). The budget gate now lives in the cron commands themselves:
--  * ripples.att_social_jet_budget(lane) syncs today's bsky.jet att_budget cap to att_sources.per_day_cap on every
--    tick (so a stale frozen cap can never stall the stream again) and answers whether that lane may spend a unit;
--  * the buffer-replay lane only runs while the budget left is above the live reserve (remaining 5-min slots today
--    + 12), so it can never starve the live cadence;
--  * no edge invocation at all when the budget is spent or the bucket is killed (no more no-op calls every minute).
select cron.alter_job((select jobid from cron.job where jobname = 'att-jetstream'), command => $cmd$
  select public.call_collector('att-social', '{"mode":"jetstream"}'::jsonb)
  where coalesce((ripples.att_social_jet_budget('live')->>'ok')::boolean, false)
$cmd$);

select cron.alter_job((select jobid from cron.job where jobname = 'att-jetstream-catchup'), command => $cmd$
  with st as (
    select coalesce((select (v->>'cursor')::bigint from ripples.att_state where k = 'jet.cursor'), 0)
             < (extract(epoch from now()) * 1e6)::bigint - 1800000000 as lagging,
           exists (select 1 from ripples.att_state where k = 'jet.bf'
                    and (v->>'cursor')::bigint < (v->>'until')::bigint) as replay)
  select public.call_collector('att-social',
           case when lagging then '{"mode":"jetstream"}' else '{"mode":"jetstream","params":{"lane":"backfill"}}' end::jsonb)
  from st
  where extract(minute from now())::int % 5 <> 1
    and ((lagging and coalesce((ripples.att_social_jet_budget('live')->>'ok')::boolean, false))
      or (not lagging and replay and coalesce((ripples.att_social_jet_budget('backfill')->>'ok')::boolean, false)))
$cmd$);
