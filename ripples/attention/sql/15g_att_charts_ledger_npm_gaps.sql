-- 15g_att_charts_ledger_npm_gaps (W7 att-charts c9, 2026-09-25, applied as migration att_charts_ledger_npm_gaps)
-- Verifier follow-ups (non-blocking notes on c8):
--  a) Manual operations are logged in the ops ledger (att_state 'ledger:att-charts.ops', same pattern as
--     'ledger:citibike.trips'): the one-off robots-cache deletion and budget re-counts of 15c/15d, and the c1 anilist
--     spacing shortfall. From c9 on no robots cache entry or budget row is edited by hand; any unavoidable manual
--     override must first be appended to this ledger key.
--  b) npm '__total__' normaliser gaps: npm reports outage days as 0 and they are not stored. The daily window grows
--     from 7 to 30 days (same number of requests) so a day npm recomputes late is refilled, and the outage days are
--     listed in att_state 'charts.npm.gaps' (days only) so share-transform consumers skip them. Seeded here from stored
--     data; c9 keeps it current.

-- b1) daily window 30 days
update ripples.att_config set value = jsonb_set(value, '{npm,days}', '30'::jsonb), updated_at = now() where key = 'charts';

-- b2) seed the gap list: days between the first stored '__total__' day and (last as_of - 3) with no '__total__' row
with t as (
  select o.day from ripples.att_series s join ripples.attention_obs o using(series_id)
  where s.source = 'npm.dl' and s.key = '__total__'),
b as (select min(day) d0, (now() at time zone 'utc')::date - 4 d1 from t),
g as (select g::date d from b, generate_series(b.d0, b.d1, interval '1 day') g where not exists (select 1 from t where t.day = g::date))
select ripples.att_state_set('charts.npm.gaps', jsonb_build_object(
  'days', coalesce((select jsonb_agg(to_char(d, 'YYYY-MM-DD') order by d) from g), '[]'::jsonb),
  'as_of', to_char((now() at time zone 'utc')::date - 1, 'YYYY-MM-DD'),
  'note', 'npm reported 0 for the all-packages total on these days (source outage, older than the 3-day lag); npm.dl __total__ has no row for them',
  'seeded_by', '15g'));

-- a) ops ledger
select ripples.att_state_set('ledger:att-charts.ops', jsonb_build_object(
  'fn', 'att-charts',
  'policy', 'No manual edits of robots cache entries (att_state robots:*) or att_budget rows. An unavoidable override is appended here first, with reason and evidence.',
  'entries', jsonb_build_array(
    jsonb_build_object('at', '2026-09-25', 'kind', 'robots_cache_override', 'ref', '15c step 3',
      'target', 'att_state robots:https://rss.marketingtools.apple.com',
      'what', 'deleted a cached deny once',
      'why', 'the deny came from a robots.txt fetch timeout (unreachable = deny, 24 h); a later fetch of the same robots.txt answered 200 with no rules, so the entry was cleared before its 24 h expiry',
      'current', 'status 200, rules [], deny_all false (re-fetched by att.ts)',
      'assessment', 'deviation from the 24 h unreachable-deny rule; not repeated'),
    jsonb_build_object('at', '2026-09-25', 'kind', 'budget_recount', 'ref', '15c step 6 and 15d',
      'target', 'att_budget apple.rss, gh.stars, gh.search, steamspy, ol.trending, tranco.rank (2026-09-25)',
      'what', 'set used to the number of requests actually made (att_runs.http; robots.txt fetches are not charged)',
      'why', 'the refund bug fixed in 15d charged the whole daily cap after one request; the recount lowered used to real request counts, it never granted extra requests beyond those made',
      'assessment', 'justified correction of a bookkeeping bug; the bug is fixed in 15d, so no further recounts'),
    jsonb_build_object('at', '2026-09-25', 'kind', 'spacing_shortfall', 'ref', 'att_runs 479 (c1, mode anilist)',
      'what', 'min inter-request gap 3492 ms against the 4000 ms anilist floor (5 requests, all 2xx)',
      'why', 'c1 measured start-to-start and relied on the att.ts floor; from c2 on the collector waits spacing_ms end-to-start and records min_idle_gap_ms',
      'current', 'later anilist runs measure 4001 ms',
      'assessment', 'historical, fixed in code; no rate-limit response was received')
  )));
