-- 29_att_youtube (2026-09-26) — YouTube Data API v3 attention collector (att-youtube).
--
-- Reuses the placeholder source row `yt.api` that was already registered (disabled) for exactly this build, rather
-- than adding a second source id: enables it, points needs_secret at the real Vault secret name (`youtube_api_key`,
-- not the placeholder's `youtube_key`), gives it a dedicated daily budget bucket, and tightens spacing/caps so a
-- full daily pass (40 regions x 7 categories = 280 videos.list calls, 1 unit each) fits the WALL_MS budget.
--
-- Terms / storage (YouTube API Services Terms, "cached data" rule -> refresh or delete raw API data within 30 days):
--   * NOTHING per-video is stored in ripples tables. The only raw cache is two rows in ripples.att_state
--     (keys 'yt.raw.prev' / 'yt.raw.curr': {day, combos: {"<region>|<category>": {<video_id>: <view_count>, ...}}}),
--     rotated once per UTC day (curr -> prev, new empty curr) so the OLDEST raw video-level numbers on disk are
--     always < 48h old -- far inside the 30-day API-Services-Terms cap and the 28-day cap this project sets itself.
--     A cron safety-net (att-youtube-raw-cleanup) also deletes any 'yt.raw%' state row older than 28 days, in case
--     the rotation ever stalls.
--   * Only DERIVED aggregates are persisted long-term in ripples.attention_obs: per region x category top-50 view
--     sum, median per-video view velocity (vs the previous day's snapshot of the SAME video ids), a new-entrant
--     count, and a per-topic "how many of today's trending videos match this topic's label" count. No commenter or
--     viewer identity of any kind is read or stored (aggregate counts only); channel titles are read only to decide
--     ranking and are never persisted.
--   * license_note on att_sources carries this summary for auditors.

-- ------------------------------------------------------------------ att_sources: enable + fix up the placeholder
update ripples.att_sources set
  enabled       = true,
  needs_secret  = 'youtube_api_key',
  budget_bucket = 'youtube',
  spacing_ms    = 300,           -- keyed commercial API, generous published quota; polite serial pacing only
  per_run_cap   = 320,           -- 280 combos/day + headroom for probe/peek calls in the same run
  per_day_cap   = null,          -- capped by the shared 'youtube' budget bucket instead (att_config.budgets)
  history_from  = current_date,
  value_kind    = 'level',
  channel       = 'consumption',
  engine_channel = 'CONS',
  attribution   = 'YouTube Data API v3 (Google)',
  license_note  = 'Documented keyed API (videos.list chart=mostPopular), 1 unit/call. YouTube API Services Terms: '
    || 'raw per-video stats are cached at most ~48h (ripples.att_state, rotated daily) then discarded; only '
    || 'derived aggregates (region x category view-sum, median view-velocity z, new-entrant counts, per-topic hit '
    || 'counts) are stored long-term. No personal data; channel titles read only, never stored.',
  reason        = null
where source = 'yt.api';

-- ------------------------------------------------------------------ engine channel map
insert into ripples.att_engine_source_map (source, channel, value_kind, same_dow, agg_key, domain, metric_kinds)
values ('yt.api', 'CONS', 'level', false, null, 'consumption',
  jsonb_build_object('views_top50', 'level', 'entrants', 'count', 'velocity_median', 'rate', 'topic_hits', 'count'))
on conflict (source) do update set
  channel = excluded.channel, value_kind = excluded.value_kind, same_dow = excluded.same_dow,
  agg_key = excluded.agg_key, domain = excluded.domain, metric_kinds = excluded.metric_kinds;

-- ------------------------------------------------------------------ budget bucket (att_take_budget reads
-- att_config.budgets->>'youtube' because att_sources.budget_bucket = 'youtube' is not itself a source id).
-- 280 units/day expected (40 regions x 7 categories x 1 unit); capped well under the owner's 3,000/day ceiling and
-- far under YouTube's 10,000/day project quota.
update ripples.att_config set value = value || jsonb_build_object('youtube', 3000), updated_at = now()
where key = 'budgets';

-- ------------------------------------------------------------------ topics RPC: the small, fixed panel of active
-- topics att-youtube matches trending video titles against (word-boundary, case-insensitive). Kept separate from
-- att_watchlist (which serves the term-tracking social/news collectors with different key_type semantics).
create or replace function ripples.att_yt_topics(p_limit int default 300)
returns table (topic_id bigint, label text, label_key text)
language sql stable security definer set search_path = ''
as $$
  select topic_id, label, label_key
  from ripples.att_topics
  where status = 'active' and in_panel = true and length(label) >= 3
  order by topic_id
  limit greatest(1, p_limit)
$$;

create or replace function public.att_yt_topics(p_limit int default 300)
returns table (topic_id bigint, label text, label_key text)
language sql security definer set search_path = ''
as $$ select * from ripples.att_yt_topics(p_limit) $$;

revoke all on function public.att_yt_topics(int) from public, anon, authenticated;
grant execute on function public.att_yt_topics(int) to service_role;
revoke all on function ripples.att_yt_topics(int) from public, anon, authenticated;
grant execute on function ripples.att_yt_topics(int) to service_role;

-- ------------------------------------------------------------------ raw-cache safety-net cleanup (see header: the
-- collector itself rotates 'yt.raw.prev'/'yt.raw.curr' every UTC day, so this should normally delete 0 rows).
create or replace function ripples.att_yt_raw_cleanup(p_keep_days int default 28)
returns int
language sql security definer set search_path = ''
as $$
  with d as (
    delete from ripples.att_state
    where k like 'yt.raw%' and updated_at < now() - make_interval(days => greatest(1, p_keep_days))
    returning 1
  )
  select count(*)::int from d
$$;

create or replace function public.att_yt_raw_cleanup(p_keep_days int default 28)
returns int
language sql security definer set search_path = ''
as $$ select ripples.att_yt_raw_cleanup(p_keep_days) $$;

revoke all on function public.att_yt_raw_cleanup(int) from public, anon, authenticated;
grant execute on function public.att_yt_raw_cleanup(int) to service_role;
revoke all on function ripples.att_yt_raw_cleanup(int) from public, anon, authenticated;
grant execute on function ripples.att_yt_raw_cleanup(int) to service_role;

-- ------------------------------------------------------------------ cron
-- Primary daily pass at a quiet minute, plus two same-day catch-up slots (the collector is idempotent and
-- cursor-resumable via att_state 'yt.day', so a slow day just finishes on the next slot instead of being lost;
-- this mirrors the existing multi-slot pattern used by att-wiki-pv / att-apple).
select cron.schedule('att-youtube', '23 7 * * *',
  $$select public.call_collector('att-youtube', '{"mode":"collect"}'::jsonb)$$);
select cron.schedule('att-youtube-2', '33 7 * * *',
  $$select public.call_collector('att-youtube', '{"mode":"collect"}'::jsonb)$$);
select cron.schedule('att-youtube-3', '43 7 * * *',
  $$select public.call_collector('att-youtube', '{"mode":"collect"}'::jsonb)$$);
-- 28-day raw-cache safety net (see ripples.att_yt_raw_cleanup above).
select cron.schedule('att-youtube-raw-cleanup', '11 3 * * *',
  $$select ripples.att_yt_raw_cleanup(28)$$);
