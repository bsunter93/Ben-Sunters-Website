-- Migration `att_market_fixes` (W7 att-market builder, 2026-09-25, after independent verification).
-- 1. att_market_clear_day: drop one snapshot day's vol24h rows (and that day's candidates) of a prediction-market source
--    before a fresh snapshot is written, so a day never mixes two snapshots (Kalshi crawl restart, Polymarket re-run).
--    Restricted to poly.mkt / kalshi.mkt and metric vol24h; service_role only.
-- 2. Data fix: remove the false zeros written by the FINRA ticker backfill for days before the ticker's first reported
--    volume (the FINRA Query API keeps ~1 year of regShoDaily; days outside it are "no data", not 0).
create or replace function ripples.att_market_clear_day(p_source text, p_day date)
returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer := 0; c integer := 0;
begin
  if p_source not in ('poly.mkt', 'kalshi.mkt') then raise exception 'att_market_clear_day: source % not allowed', p_source; end if;
  delete from ripples.attention_obs o using ripples.att_series s
   where s.series_id = o.series_id and s.source = p_source and s.metric = 'vol24h' and o.day = p_day;
  get diagnostics n = row_count;
  delete from ripples.att_trend_candidates t where t.source = p_source and t.day = p_day;
  get diagnostics c = row_count;
  return n + c;
end $$;
create or replace function public.att_market_clear_day(p_source text, p_day date)
returns integer
language sql security definer set search_path = '' as
$$ select ripples.att_market_clear_day(p_source, p_day) $$;
do $$ declare f text; begin
  foreach f in array array['ripples.att_market_clear_day(text, date)', 'public.att_market_clear_day(text, date)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- 2. false FINRA zeros (before each ticker series' first non-zero observation)
delete from ripples.attention_obs o
 using ripples.att_series s
 where s.series_id = o.series_id and s.source = 'finra.shvol' and s.key <> '__total__' and o.value = 0
   and o.day < (select min(o2.day) from ripples.attention_obs o2 where o2.series_id = s.series_id and o2.value > 0);

-- ---- applied 2026-09-25 ~18:03 UTC with function version 2026-09-25.m7 (deploy v9). Result: META 275 -> 251 obs,
-- 0 zeros, first day 2025-09-25 (the 24 false zeros for 2025-08-21..2025-09-24 removed). att_market_clear_day was tested
-- inside a rolled-back block (kalshi.mkt 2026-09-25: 250 rows before, 250 cleared, 0 after; rolled back).
-- m7 code changes (functions/att-market/index.ts):
--   * finraKeysBackfill: zeros only from the ticker's first reported day (and >= finra.state.floor); nothing before.
--   * finraFilesBackfill: finra.state.nodata no longer truncated to 50 (kept for the whole target window); retention
--     floor finra.state.floor set when the 3 trading days right below the oldest mirrored day are all empty; target and
--     missing_left count only days >= floor, so the job finishes (att_jobs 'done') at the retention edge.
--   * finra daily: a day that is still unpublished (< 5 calendar days old) is not remembered as nodata.
--   * USAspending: timeouts counted per UTC day across runs in att_state 'usasp.slow'; at 3 the host is stopped for the
--     rest of the UTC day (no request from rotation or backfill; backfill jobs deferred to 00:10 UTC).
--   * Kalshi: a same-day crawl whose last chunk is older than 2 h is restarted from page 1 and that day's earlier
--     kalshi.mkt vol24h rows + candidates are cleared first (no stitching of snapshots hours apart, no stale cursor).
--   * Polymarket: a complete snapshot replaces the day's earlier vol24h rows + candidates (price series untouched).
