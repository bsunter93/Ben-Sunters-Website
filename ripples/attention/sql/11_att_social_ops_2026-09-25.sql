-- Operational record for att-social (W7 att-social builder, 2026-09-25). Statements executed with execute_sql, not
-- migrations; kept here so the state can be rebuilt.

-- 1) One-off Jetstream buffer replay ("backfill lane"): from 34 h ago up to the first live cursor (run 18 started the
--    live lane at 1790313642080000 us = 2026-09-25 05:20:42 UTC). The live lane (jet.cursor) and the backfill lane
--    (jet.bf) never overlap, so nothing is counted twice. The att-jetstream-catchup cron drives it every minute
--    (except the :x1/:x6 live slots) until jet.bf.cursor >= jet.bf.until.
select ripples.att_state_set('jet.bf', jsonb_build_object(
  'cursor', (extract(epoch from now() - interval '34 hours') * 1e6)::bigint,
  'until', 1790313642080000::bigint,
  'note', 'one-off replay of the Jetstream buffer up to where the live lane started'));

-- 2) The first catch-up run streamed 20 min on a cold isolate and hit WORKER_RESOURCE_LIMIT (HTTP 546, no data
--    written, cursor not advanced). The processing budget per run was lowered from 1100 ms to 800 ms.
update ripples.att_config set value = value || '{"jet_proc_ms":800}'::jsonb, updated_at = now() where key = 'social';

-- 3) HN rows written by the first daily run (before queryType=prefixNone / restrictSearchableAttributes were added)
--    were deleted and the rotation reset; totals ('__total__') were kept.
delete from ripples.attention_obs o using ripples.att_series s
 where s.series_id = o.series_id and s.source = 'hn.algolia' and s.key <> '__total__'
   and o.day between '2026-09-22' and '2026-09-24';
select ripples.att_state_set('hn.rot', '{"off":0}');

-- 4) (retry session, ~15:05 UTC) se.api backfill dispatches were no-ops every 2 min once the se.api daily budget was
--    spent (Run.finish requeued them for +1 h). att-social s4 now defers them to the next UTC day itself
--    (deferIfHostClosed); the 216 jobs already queued for today were deferred once by hand:
update ripples.att_jobs set not_before = '2026-09-26 00:10:00+00', error = 'deferred: daily_budget_spent:se.api (ops 2026-09-25)'
 where fn = 'att-social' and status = 'queued' and payload->'params'->>'source' = 'se.api' and not_before < '2026-09-26';
