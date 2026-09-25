-- 17_att_econ (v6 WS-A, 2026-09-25; applied as migration att_econ_sources)
-- Outcome-data sources for the Ripple Map engine (ENGINE_SPEC §1.1, §9, §10.2) + the equities collector (OWNER D-10),
-- NOAA GHCN-Daily (D-9) and Census business applications (D-7).
--
-- * att_sources: grade 'orange' (ORANGE*, DEMARCATION §1.3, owner-approved D-10) and value_kind 'rate' (ENGINE §3.1:
--   yields, spreads, probabilities, our own z-scores: no log transform) are added to the checks.
-- * att_sources.engine_channel: the ENGINE channel code (READ ... MONEY) for EVERY source; the legacy lower-case
--   `channel` column is kept unchanged for v5 code. att_channel_stat (ENGINE §10.2) holds kind / statistic / clock.
-- * New source rows (all GREEN except the two equities rows): eia.930, eia.prices, fred, bls.ces, bls.cpi_items,
--   dol.claims, noaa.ghcnd, census.bfs, wikidata.entity. twelvedata / alphavantage rows are re-graded ORANGE*.
-- * Budget buckets (att_take_budget): eia 500/day, fred 300/day, bls 100/day, noaa 2000/day, census 100/day,
--   wikidata raised 300 -> 550 (registry 300 + EntityData claims 250).
-- * Keys are read ONLY at run time through public.att_secret('<name>') (service_role). Nothing here contains a key.
-- * att_release_dates: official release calendars (FRED release/dates API) for release-look tests (ENGINE §3.6, §7).

-- ------------------------------------------------------------------ checks
alter table ripples.att_sources drop constraint if exists att_sources_grade_check;
alter table ripples.att_sources add constraint att_sources_grade_check
  check (grade = any (array['green','yellow','orange']));
alter table ripples.att_sources drop constraint if exists att_sources_value_kind_check;
alter table ripples.att_sources add constraint att_sources_value_kind_check
  check (value_kind = any (array['count','share','rank','bucket','index','level','rate']));

-- ------------------------------------------------------------------ channel statistic table (ENGINE §1.1, §3.6, §10.2)
create table if not exists ripples.att_channel_stat (
  channel text primary key,
  kind text not null check (kind in ('attention','outcome')),
  stat_kind text not null check (stat_kind in ('peak','car','release')),
  l_days smallint not null,
  sided text not null default 'signed',
  min_kappa_measured real not null default 0.5,
  -- additive (WS-A): weekly/monthly series of the channel are tested at release looks with the slow clock
  stat_kind_slow text check (stat_kind_slow in ('peak','car','release')),
  l_days_slow smallint,
  active boolean not null default true,
  label text,
  note text
);
alter table ripples.att_channel_stat enable row level security;
revoke all on ripples.att_channel_stat from public, anon, authenticated;
grant select on ripples.att_channel_stat to service_role;

insert into ripples.att_channel_stat (channel, kind, stat_kind, l_days, stat_kind_slow, l_days_slow, active, label, note) values
 ('READ', 'attention','peak',   3, null, null, true, 'Reading',       'wiki.pv (all languages = one channel), wiki.topcc'),
 ('SRCH', 'attention','peak',   3, null, null, true, 'Search',        'gt.rss is discovery only (no series); Trends alpha when granted'),
 ('SOC',  'attention','peak',   2, null, null, true, 'Social',        'hn.algolia, se.api, masto.tags, bsky.jet'),
 ('NEWS', 'attention','peak',   2, null, null, true, 'News',          'gdelt.gkg, news.sitemap'),
 ('TV',   'attention','peak',   2, null, null, true, 'TV',            'ia.thirdeye'),
 ('PM',   'outcome',  'peak',   4, null, null, true, 'Prediction markets', 'poly.mkt (p, vol24h), kalshi.mkt'),
 ('BLD',  'outcome',  'car',   14, null, null, true, 'Builders',      'npm.dl, pypi.dl, gh.stars, hf.trending'),
 ('CONS', 'outcome',  'car',   14, null, null, true, 'Consumption',   'anilist, apple.rss, steamspy, ol.trending, tranco.rank'),
 ('PHYS', 'outcome',  'car',    7, null, null, true, 'Real world',    'tsa.pax, mta.ridership, citibike.trips, eia.930, usgs.eq; noaa.ghcnd/gdacs are upstream shocks'),
 ('JOBS', 'outcome',  'release',28,'release',90, true, 'Jobs',        'dol.claims weekly (28 d), bls.ces monthly (90 d); hiringlab.postings daily uses the 28-day slope (ENGINE §1.1)'),
 ('INST', 'outcome',  'car',   90,'release',90, true, 'Institutions', 'fema.decl, iem.warn daily (CAR); usasp.spend, sec.efts monthly (release look)'),
 ('ECON', 'outcome',  'peak',   4,'release',90, true, 'Economy',      'fred, eia.prices daily (peak, 4 d); bls.cpi_items, census.bfs weekly/monthly (release look)'),
 ('MONEY','outcome',  'peak',   4, null, null, false,'Markets',       'D-10: equities collected as derived abnormal-volume/return z only (twelvedata, alphavantage). ENGINE §1.1/§8 still disable MONEY: inactive until the lead re-enables it in the engine')
on conflict (channel) do update set kind = excluded.kind, stat_kind = excluded.stat_kind, l_days = excluded.l_days,
  stat_kind_slow = excluded.stat_kind_slow, l_days_slow = excluded.l_days_slow, active = excluded.active,
  label = excluded.label, note = excluded.note;

alter table ripples.att_sources add column if not exists engine_channel text references ripples.att_channel_stat(channel);

-- ------------------------------------------------------------------ new source rows
insert into ripples.att_sources (source, family, channel, grade, value_kind, grain, history_from, enabled, reason,
  needs_secret, tier, attribution, license_note, per_run_cap, per_day_cap, spacing_ms, budget_bucket, hosts,
  robots_required, backfill_fn, engine_channel) values
 ('eia.930', 'eia', 'physical', 'green', 'level', 'day', '2015-07-01', true,
  'EIA API v2 (documented, keyed). Published limit ~5,000 req/h -> budget 500/day shared bucket eia, 1 req/2 s. Daily demand (type D) per balancing authority and region; one call returns up to 5,000 rows',
  'eia_api_key', 'ship', 'U.S. Energy Information Administration, Hourly Electric Grid Monitor (EIA-930)',
  'Public domain (U.S. government); cite EIA', 40, null, 2000, 'eia', array['api.eia.gov'], true, 'att-econ', 'PHYS'),
 ('eia.prices', 'eia', 'money', 'green', 'level', 'day', '1986-01-02', true,
  'EIA API v2 seriesid route: WTI, Brent spot, Henry Hub spot (daily), retail gasoline/diesel by PADD (weekly). Bucket eia',
  'eia_api_key', 'ship', 'U.S. Energy Information Administration (spot prices; Gasoline and Diesel Fuel Update)',
  'Public domain (U.S. government); cite EIA', 20, null, 2000, 'eia', array['api.eia.gov'], true, 'att-econ', 'ECON'),
 ('fred', 'fred', 'money', 'green', 'level', 'day', '2016-01-01', true,
  'FRED API (documented, keyed): 120 req/min published -> 1 req/1.5 s, 300/day bucket fred. Only government-origin series (Board of Governors H.15/H.10, DOL, EIA); third-party series (Cboe VIX, S&P 500, ICE BofA, Freddie Mac) are excluded',
  'fred_api_key', 'ship', 'FRED, Federal Reserve Bank of St. Louis (source agencies: Board of Governors of the Federal Reserve System, U.S. Department of Labor, U.S. EIA)',
  'FRED terms of use; only public-domain government series stored; vintages (realtime_start) and first-release dates kept in meta', 60, null, 1500, 'fred', array['api.stlouisfed.org'], true, 'att-econ', 'ECON'),
 ('bls.ces', 'bls', 'institutional', 'green', 'level', 'month', '2016-01-01', true,
  'BLS Public Data API v2 (keyed): 500 queries/day published -> budget 100/day bucket bls, 50 series per query, 1 req/5 s',
  'bls_api_key', 'ship', 'U.S. Bureau of Labor Statistics, Current Employment Statistics (CES), seasonally adjusted',
  'Public domain (U.S. government); cite BLS', 10, null, 5000, 'bls', array['api.bls.gov'], true, 'att-econ', 'JOBS'),
 ('bls.cpi_items', 'bls', 'money', 'green', 'index', 'month', '2016-01-01', true,
  'BLS Public Data API v2 (keyed), CPI-U item indexes (SA where published, else NSA); bucket bls',
  'bls_api_key', 'ship', 'U.S. Bureau of Labor Statistics, Consumer Price Index (CPI-U, U.S. city average)',
  'Public domain (U.S. government); cite BLS', 10, null, 5000, 'bls', array['api.bls.gov'], true, 'att-econ', 'ECON'),
 ('dol.claims', 'dol', 'institutional', 'green', 'count', 'week', '1971-01-01', true,
  'U.S. DOL ETA weekly claims file ar539.csv (keyless, published open data). No published limit -> Q6 1 req/5 s; one download per week',
  null, 'ship', 'U.S. Department of Labor, Employment and Training Administration, weekly claims (ETA 539)',
  'Public domain (U.S. government); cite DOL ETA', 2, 4, 5000, null, array['oui.doleta.gov'], true, 'att-econ', 'JOBS'),
 ('noaa.ghcnd', 'noaa', 'physical', 'green', 'level', 'day', '2015-01-01', true,
  'NOAA NCEI Climate Data Online API v2 (token): 5 req/s and 10,000/day published -> 1 req/0.5 s, 2,000/day bucket noaa. GHCN-Daily TMAX/TMIN/PRCP for ~70 first-order stations (1-3 per state)',
  'noaa_cdo_token', 'ship', 'NOAA National Centers for Environmental Information, GHCN-Daily (Menne et al.)',
  'Public domain (U.S. government); cite NOAA NCEI GHCN-Daily', 150, null, 500, 'noaa', array['www.ncei.noaa.gov'], true, 'att-econ', 'PHYS'),
 ('census.bfs', 'census', 'institutional', 'green', 'count', 'week', '2006-01-01', true,
  'U.S. Census Bureau Business Formation Statistics (weekly business applications, national + states). Census API key held for api.census.gov; no published limit for the CSV -> Q6 1 req/5 s',
  'census_api_key', 'ship', 'U.S. Census Bureau, Business Formation Statistics',
  'Public domain (U.S. government); cite U.S. Census Bureau BFS', 4, 10, 5000, 'census', array['api.census.gov','www.census.gov'], true, 'att-econ', 'ECON'),
 ('wikidata.entity', 'wikimedia', 'reading', 'green', 'count', 'day', null, true,
  'Wikidata Special:EntityData/{QID}.json (robots-allowed documented linked-data channel, DEMARCATION §1.4 hole type 1). Serial >= 1.1 s, honest UA with contact, no retry after 429/503; shared bucket wikidata (<= 250 claims calls/day). Graph edges only, no observations',
  null, 'ship', 'Wikidata (CC0)', 'CC0', 80, null, 1100, 'wikidata', array['www.wikidata.org'], true, 'att-wikidata', 'READ')
on conflict (source) do update set family = excluded.family, channel = excluded.channel, grade = excluded.grade,
  value_kind = excluded.value_kind, grain = excluded.grain, history_from = excluded.history_from, enabled = excluded.enabled,
  reason = excluded.reason, needs_secret = excluded.needs_secret, tier = excluded.tier, attribution = excluded.attribution,
  license_note = excluded.license_note, per_run_cap = excluded.per_run_cap, per_day_cap = excluded.per_day_cap,
  spacing_ms = excluded.spacing_ms, budget_bucket = excluded.budget_bucket, hosts = excluded.hosts,
  robots_required = excluded.robots_required, backfill_fn = excluded.backfill_fn, engine_channel = excluded.engine_channel;

-- Equities (OWNER D-10: ORANGE* approved; DEMARCATION §1.3 three conditions). Derived z only; enabled only while the
-- Vault key exists (att-equities checks att_secret at run time and no-ops without it).
update ripples.att_sources set grade = 'orange', tier = 'key', value_kind = 'rate', grain = 'day', channel = 'money',
  engine_channel = 'MONEY', needs_secret = 'twelvedata_api_key', policy_d1 = false, enabled = true,
  per_run_cap = 7, per_day_cap = 400, spacing_ms = 15000, budget_bucket = null, hosts = array['api.twelvedata.com'],
  robots_required = true, backfill_fn = 'att-equities',
  reason = 'ORANGE* owner-approved (D-10, 2026-09-25). Free Basic plan: 800 credits/day, 8/min published -> <= 50%: 400/day, 1 req/15 s (4/min). One credit per symbol call. Stores ONLY derived abnormal-volume z and return z per trading day; raw prices/volumes are never stored or republished; no tickers in open-data files',
  attribution = 'Market data: Twelve Data (derived statistics only)',
  license_note = 'Twelve Data terms (free Basic plan). Derived z only; check commercial-use terms before any paid surface'
 where source = 'twelvedata';
update ripples.att_sources set grade = 'orange', tier = 'key', value_kind = 'rate', grain = 'day', channel = 'money',
  engine_channel = 'MONEY', needs_secret = 'alphavantage_api_key', policy_d1 = false, enabled = true,
  per_run_cap = 6, per_day_cap = 12, spacing_ms = 15000, budget_bucket = null, hosts = array['www.alphavantage.co'],
  robots_required = true, backfill_fn = 'att-equities',
  reason = 'ORANGE* owner-approved (D-10, 2026-09-25). Free tier 25 requests/day published -> <= 50%: 12/day, 1 req/15 s. TIME_SERIES_DAILY compact (100 days) as a second route for sector ETFs. Derived z only',
  attribution = 'Market data: Alpha Vantage (derived statistics only)',
  license_note = 'Alpha Vantage terms (free tier). Derived z only; check commercial-use terms before any paid surface'
 where source = 'alphavantage';

-- engine_channel for every existing source (ENGINE §1.1). Graph-only sources (wikidata.*) sit in READ and emit no series.
update ripples.att_sources set engine_channel = case
  when source like 'wiki.%' or source in ('wikidata.api','wikidata.entity','wme.realtime') then 'READ'
  when source in ('gt.rss','gt.alpha','bing.wm','brave.suggest','dfs.ac','dfs.amazon','dfs.trends','glimpse','pinterest.trends') then 'SRCH'
  when source in ('hn.algolia','se.api','masto.tags','masto.trends','bsky.jet','bsky.trends','reddit.api','x.api','tiktok.vendor') then 'SOC'
  when source in ('gdelt.gkg','gdelt.bq','news.sitemap','guardian.api','nyt.api','mediacloud','eventregistry') then 'NEWS'
  when source in ('ia.thirdeye') then 'TV'
  when source in ('poly.mkt','kalshi.mkt') then 'PM'
  when source in ('npm.dl','pypi.dl','gh.stars','gh.search','hf.trending') then 'BLD'
  when source in ('anilist','apple.rss','apple.music','steamspy','steam.api','ol.trending','tranco.rank','appfigures',
                  'netflix.top10','podcastindex','similarweb','tmdb.trending','twitch.helix','yt.api','card.spend') then 'CONS'
  when source in ('tsa.pax','mta.ridership','citibike.trips','eia.930','usgs.eq','gdacs','flightaware','noaa.ghcnd') then 'PHYS'
  when source in ('hiringlab.postings','dol.claims','bls.ces') then 'JOBS'
  when source in ('fema.decl','iem.warn','usasp.spend','sec.efts','nws.alerts') then 'INST'
  when source in ('fred','eia.prices','bls.cpi_items','census.bfs') then 'ECON'
  when source in ('twelvedata','alphavantage','finra.api','finra.shvol','polygon','coingecko') then 'MONEY'
  else engine_channel end;

-- ------------------------------------------------------------------ budgets, meta keys, config
update ripples.att_config set value = coalesce(value, '{}'::jsonb)
  || '{"eia": 500, "fred": 300, "bls": 100, "noaa": 2000, "census": 100, "wikidata": 550}'::jsonb, updated_at = now()
 where key = 'budgets';
update ripples.att_config set value = (select to_jsonb(array_agg(distinct x order by x)) from (
    select jsonb_array_elements_text(value) x union all
    select unnest(array['vintage','released','ref','prelim','tz','unit','sa','flag','n_obs']) ) z), updated_at = now()
 where key = 'meta_allow';
insert into ripples.att_config(key, value) values ('econ', '{
  "fred_from": "2016-01-01", "eia930_from": "2015-07-01", "bls_from_year": 2016, "noaa_from": "2019-01-01",
  "bfs_from": "2016-01-01", "eia_len": 5000
}'::jsonb) on conflict (key) do nothing;

-- ------------------------------------------------------------------ release calendars (ENGINE §3.6 release looks, §7)
create table if not exists ripples.att_release_dates (
  release text not null,               -- 'cpi' | 'jobs' | 'fomc' | 'claims' | 'gdp' | 'pce' ...
  release_date date not null,
  fred_release_id int,
  scheduled boolean not null default false,   -- date in the future when fetched (from the official schedule)
  fetched_at timestamptz not null default now(),
  primary key (release, release_date)
);
alter table ripples.att_release_dates enable row level security;
revoke all on ripples.att_release_dates from public, anon, authenticated;
grant select on ripples.att_release_dates to service_role;

create or replace function ripples.att_release_upsert(p_rows jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into ripples.att_release_dates(release, release_date, fred_release_id, scheduled, fetched_at)
  select r->>'release', (r->>'date')::date, nullif(r->>'fred_release_id','')::int,
         coalesce((r->>'date')::date > (now() at time zone 'utc')::date, false), now()
    from jsonb_array_elements(p_rows) r
   where r->>'release' ~ '^[a-z_]{2,20}$' and r->>'date' ~ '^\d{4}-\d{2}-\d{2}$'
  on conflict (release, release_date) do update set fred_release_id = excluded.fred_release_id,
    scheduled = excluded.scheduled, fetched_at = now();
  get diagnostics n = row_count;
  return n;
end $$;

-- Monthly BLS observations (day = first day of the reference month): released = first official release date strictly
-- after the end of the reference month (handles the 2025 shutdown delays: e.g. Sep-2025 jobs -> 2025-11-20).
create or replace function ripples.att_econ_apply_releases() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_ces int; n_cpi int;
begin
  update ripples.attention_obs o set meta = coalesce(o.meta, '{}'::jsonb) || jsonb_build_object('released', r.d::text)
    from ripples.att_series s,
         lateral (select min(rd.release_date) d from ripples.att_release_dates rd
                   where rd.release = 'jobs' and rd.release_date > (o.day + interval '1 month' - interval '1 day')::date) r
   where s.series_id = o.series_id and s.source = 'bls.ces' and r.d is not null
     and (o.meta->>'released') is distinct from r.d::text;
  get diagnostics n_ces = row_count;
  update ripples.attention_obs o set meta = coalesce(o.meta, '{}'::jsonb) || jsonb_build_object('released', r.d::text)
    from ripples.att_series s,
         lateral (select min(rd.release_date) d from ripples.att_release_dates rd
                   where rd.release = 'cpi' and rd.release_date > (o.day + interval '1 month' - interval '1 day')::date) r
   where s.series_id = o.series_id and s.source = 'bls.cpi_items' and r.d is not null
     and (o.meta->>'released') is distinct from r.d::text;
  get diagnostics n_cpi = row_count;
  return jsonb_build_object('bls.ces', n_ces, 'bls.cpi_items', n_cpi);
end $$;

-- Coverage summary used by the acceptance checks (service only; no request is made).
create or replace function ripples.att_econ_coverage() returns jsonb
language sql stable security definer set search_path = '' as $$
  with s as (
    select s.source, s.key, s.geo, s.metric, count(o.*) n, min(o.day) d0, max(o.day) d1
      from ripples.att_series s join ripples.attention_obs o using (series_id)
     where s.source in ('eia.930','eia.prices','fred','bls.ces','bls.cpi_items','dol.claims','noaa.ghcnd','census.bfs',
                        'twelvedata','alphavantage')
     group by 1,2,3,4)
  select coalesce(jsonb_object_agg(source, j), '{}'::jsonb) from (
    select source, jsonb_build_object('series', count(*), 'rows', sum(n), 'first', min(d0), 'last', max(d1),
      'ge365_days', count(*) filter (where d1 - d0 >= 365), 'ge36_months', count(*) filter (where d1 - d0 >= 1080)) j
      from s group by source) z;
$$;

-- public wrappers (service_role only)
create or replace function public.att_release_upsert(p_rows jsonb) returns int
language sql security definer set search_path = '' as $$ select ripples.att_release_upsert(p_rows) $$;
create or replace function public.att_econ_apply_releases() returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_econ_apply_releases() $$;
revoke all on function ripples.att_release_upsert(jsonb), ripples.att_econ_apply_releases(), ripples.att_econ_coverage(),
  public.att_release_upsert(jsonb), public.att_econ_apply_releases() from public, anon, authenticated;
grant execute on function public.att_release_upsert(jsonb), public.att_econ_apply_releases() to service_role;
