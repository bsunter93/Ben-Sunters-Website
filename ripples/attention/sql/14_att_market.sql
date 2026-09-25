-- Migration `att_market_support` (W7 att-market builder, 2026-09-25).
-- Support objects for edge function att-market (modes finra, polymarket, kalshi, usaspending, edgar, backfill).
-- Everything is service_role only: RLS unchanged (no new tables), functions SECURITY DEFINER with search_path='',
-- execute revoked from anon/authenticated/PUBLIC.
--
--  * ripples.att_topic_terms(limit)            term keys + aliases + label per active/panel topic (prediction-market
--                                              title matching; no text leaves the database except these registry terms)
--  * ripples.att_series_stats(source, metric, keys, from, to)   n / mean / median per series in a day window
--                                              (poly/kalshi "volume24hr >= 3 x trailing 7-day mean" discovery rule)
--  * config 'market'                           per-run caps and thresholds (free profile; raise under 'pro')
--  * source row finra.api (inserted before this file by the builder; repeated here idempotently)
--  * att_keys for usasp.spend (+ sec.efts, disabled) for non-people topics
--  * the FINRA file backfill job
--
-- DEMARCATION Q3 note: cdn.finra.org/robots.txt answers 403 (treated as disallow; att.ts killed the host permanently on
-- 2026-09-25 15:14 UTC). The operator documents another channel, the FINRA Query API (api.finra.org, robots.txt 404,
-- anonymous access to the public regShoDaily dataset), which is graded separately as finra.api and used instead.

insert into ripples.att_sources (source, family, channel, grade, value_kind, grain, history_from, quality, enabled, reason,
  needs_secret, policy_d1, tier, attribution, license_note, per_run_cap, per_day_cap, spacing_ms, budget_bucket, hosts,
  robots_required, backfill_fn)
select 'finra.api', family, channel, 'yellow', value_kind, grain, history_from, quality, true,
  'DEMARCATION Q3: cdn.finra.org/robots.txt answers 403 (treated as disallow; host killed 2026-09-25) -> operator-documented REST channel (FINRA Query API, regShoDaily) graded separately; no published limit found -> Q6 1 req/5 s. Fetch-only source: rows are ingested as finra.shvol',
  null, false, tier, 'FINRA Query API: Reg SHO daily short sale volume', 'FINRA API terms apply; publish only z and ratios, never volumes',
  20, 500, 5000, null, array['api.finra.org'], true, 'att-market'
from ripples.att_sources where source = 'finra.shvol'
on conflict (source) do nothing;
-- one CNMS-equivalent day = ~7 pages of 5,000 rows (all TRF facilities): 500/day covers the daily file plus a
-- ~60-trading-day backfill per day at 1 request / 5 s (Q6). Rows are ingested under finra.shvol.
update ripples.att_sources set per_day_cap = 500, per_run_cap = 20, spacing_ms = 5000 where source = 'finra.api';
update ripples.att_sources
   set reason = 'Q6: no published limit -> 1 req/5 s. cdn.finra.org robots.txt 403 (disallow) since 2026-09-25: data now fetched through finra.api (FINRA Query API) and ingested under this source id'
 where source = 'finra.shvol';

-- ---------------------------------------------------------------- config
insert into ripples.att_config(key, value) values
  ('market', '{
     "poly_page": 500, "poly_max_pages": 6, "poly_min_vol24": 1000, "poly_max_markets": 300, "poly_max_events": 150,
     "poly_clob_max": 60, "poly_new_usd": 250000,
     "kalshi_page": 200, "kalshi_max_pages": 40, "kalshi_max_events": 200, "kalshi_max_markets": 100,
     "kalshi_min_mkt_vol24": 1000, "kalshi_new_contracts": 250000,
     "cand_ratio": 3, "cand_top": 30,
     "finra_page": 5000, "finra_days": 400, "finra_ring_days": 90, "finra_liq_floor": 50000,
     "finra_cand_ratio": 3, "finra_cand_z": 4, "finra_cand_top": 50, "finra_bf_days_per_run": 3,
     "usasp_rotation_days": 7, "usasp_max_keys": 12, "usasp_backfill_months": 24,
     "edgar_rotation_days": 7, "edgar_max_keys": 40
   }'::jsonb)
on conflict (key) do nothing;

-- meta keys used by att-market (stored meta is filtered through att_config.meta_allow)
update ripples.att_config
   set value = (select jsonb_agg(distinct x) from jsonb_array_elements_text(value || '["ratio","z","n_mkts","liq","facilities","new"]'::jsonb) x)
 where key = 'meta_allow';

-- ---------------------------------------------------------------- topic terms for title matching
create or replace function ripples.att_topic_terms(p_limit int default 5000)
returns table(topic_id bigint, status text, category text, terms text[])
language sql stable security definer set search_path = '' as $$
  select t.topic_id, t.status, t.category,
         array(select distinct x from (
                 select lower(t.label) as x
                 union all select lower(k.key) from ripples.att_keys k
                  where k.topic_id = t.topic_id and k.key_type = 'term' and k.enabled
                 union all select lower(a.v) from ripples.att_keys k,
                        jsonb_array_elements_text(case when jsonb_typeof(k.match->'aliases') = 'array'
                                                       then k.match->'aliases' else '[]'::jsonb end) a(v)
                  where k.topic_id = t.topic_id and k.key_type = 'term' and k.enabled) s
               where length(x) >= 4 and length(x) <= 80) as terms
  from ripples.att_topics t
  where t.status = 'active' or t.in_panel
  order by (t.status = 'active') desc, t.last_active desc nulls last, t.topic_id
  limit greatest(p_limit, 0)
$$;

-- ---------------------------------------------------------------- per-series window stats
create or replace function ripples.att_series_stats(p_source text, p_metric text, p_keys text[], p_from date, p_to date)
returns table(key text, n int, mean double precision, median double precision, first_day date)
language sql stable security definer set search_path = '' as $$
  select s.key, count(o.day)::int, avg(o.value), percentile_cont(0.5) within group (order by o.value),
         (select min(o2.day) from ripples.attention_obs o2 where o2.series_id = s.series_id)
  from ripples.att_series s
  left join ripples.attention_obs o on o.series_id = s.series_id and o.day between p_from and p_to
  where s.source = p_source and s.metric = p_metric and s.geo = 'ALL' and s.key = any(p_keys)
  group by s.key, s.series_id
$$;

-- ---------------------------------------------------------------- public wrappers (edge functions use PostgREST public)
create or replace function public.att_topic_terms(p_limit int default 5000)
returns table(topic_id bigint, status text, category text, terms text[])
language sql security definer set search_path = '' as
$$ select * from ripples.att_topic_terms(p_limit) $$;
create or replace function public.att_series_stats(p_source text, p_metric text, p_keys text[], p_from date, p_to date)
returns table(key text, n int, mean double precision, median double precision, first_day date)
language sql security definer set search_path = '' as
$$ select * from ripples.att_series_stats(p_source, p_metric, p_keys, p_from, p_to) $$;

do $$ declare f text; begin
  foreach f in array array[
    'ripples.att_topic_terms(int)', 'ripples.att_series_stats(text,text,text[],date,date)',
    'public.att_topic_terms(int)', 'public.att_series_stats(text,text,text[],date,date)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ---------------------------------------------------------------- registry keys for the institutional sources
-- usasp.spend (and sec.efts, which stays disabled) are only meaningful for non-people topics: business, tech,
-- science/health, places, events, politics. Key = the topic's longest hn.algolia term key, else its label.
-- The att_keys trigger queues one backfill job per usasp.spend key (sec.efts is disabled, so none for it).
insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, weight, verified, enabled, created_by)
select t.topic_id, s.source, 'usd', 'ALL', x.term, 'term', '{}'::jsonb, 1, false, true, 'auto'
from ripples.att_topics t
cross join lateral (select coalesce(
    (select k.key from ripples.att_keys k where k.topic_id = t.topic_id and k.source = 'hn.algolia' and k.key_type = 'term'
      order by length(k.key) desc limit 1), lower(t.label)) as term) x
cross join (values ('usasp.spend')) s(source)
where (t.status = 'active' or t.in_panel)
  and t.category in ('business', 'tech', 'science_health', 'places', 'events', 'politics')
  and length(x.term) >= 3 and x.term ~ '[a-z]' and not ripples._att_ident_like(x.term, s.source)
on conflict do nothing;
insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, weight, verified, enabled, created_by)
select k.topic_id, 'sec.efts', 'n', 'ALL', k.key, 'term', '{}'::jsonb, 1, false, true, 'auto'
from ripples.att_keys k where k.source = 'usasp.spend'
on conflict do nothing;

-- ---------------------------------------------------------------- FINRA file backfill (mirror + ring baseline)
select ripples.att_job_enqueue('backfill', 'att-market',
  '{"mode":"backfill","params":{"source":"finra.api","files":true}}'::jsonb, 4, 'finra:files', null, null);
