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
