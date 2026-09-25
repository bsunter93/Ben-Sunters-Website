-- Operational adjustments applied with execute_sql on 2026-09-25 (W7 att-core). Recorded here for reproducibility.
-- 1. AQS (wikimedia.org) returned 429 at ~4 req/s from the shared Supabase egress IP during the panel sizing run.
--    The kill switch stopped wikimedia.org until 2026-09-26 00:00 UTC, spent today's 'wikimedia' budget and set
--    tomorrow's cap to 750. Spacing for the Wikimedia sources raised to 250 ms:
update ripples.att_sources set spacing_ms = 250,
  reason = coalesce(reason || '; ', '') || 'AQS 429 seen at ~4 req/s from the shared Supabase IP on 2026-09-25: spacing 250 ms'
where source in ('wiki.pv', 'wiki.topcc', 'wiki.media');
-- 2. Panel build finished without further AQS calls: the panel.build pool was truncated to the 277 titles already
--    sized via AQS plus every en signal title whose baseline median comes from public.signal_obs (the task's named
--    sampling sources), then resolved on Wikidata and stratified (see att_state['panel.build'].summary).
