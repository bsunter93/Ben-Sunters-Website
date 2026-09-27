-- Migration: attention_stack_core  (W7 att-core, 2026-09-25)
-- ATTENTION_STACK.md §7.1 DDL, adapted to the free-tier profile (§3.8) and DEMARCATION §7 lead decisions.
-- Only ripples.att_* / ripples.attention_* objects are created. Nothing else in ripples is touched.
create extension if not exists pg_trgm with schema extensions;
create schema if not exists ripples;

-- ---------- config (free/pro switch) ----------
create table if not exists ripples.att_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
insert into ripples.att_config(key, value) values
  ('profile',            '"free"'),
  ('panel_size',         '300'),          -- pro: 1000
  ('hourly_active_only', 'true'),         -- pro: false
  ('db_cap_mb',          '400'),          -- att_ingest refuses writes above this whole-DB size
  ('budgets',            '{"wikimedia":1500,"wikidata":300}'),
  ('wm_quiet_utc',       '{"from":"06:30","to":"07:20"}'),
  ('tick',               '{"max_edge_inflight":6,"max_sql":40,"backfill_batch":25,"stuck_min":5,"max_attempts":3}'),
  ('live_fns',           '["att-registry"]'),  -- att_tick only dispatches to functions listed here
  ('ua',                 '"ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"')
on conflict (key) do nothing;

-- ---------- catalogue ----------
create table if not exists ripples.att_sources (
  source          text primary key,
  family          text not null,
  channel         text not null check (channel in
                   ('search','reading','social','news','tv','money','builder','consumption','physical','institutional')),
  grade           text not null check (grade in ('green','yellow')),   -- red sources are never inserted
  value_kind      text not null check (value_kind in ('count','share','rank','bucket','index','level')),
  grain           text not null check (grain in ('5min','15min','hour','day','week','month')),
  history_from    date,
  quality         real not null default 1.0 check (quality > 0 and quality <= 1),
  enabled         boolean not null default false,
  reason          text,                                   -- why disabled / caveat
  needs_secret    text,                                   -- vault secret name; null = none
  policy_d1       boolean not null default false,
  tier            text not null default 'ship' check (tier in ('ship','key','paid','manual','policy','test')),
  attribution     text,
  license_note    text,
  per_run_cap     int,
  per_day_cap     int,                                    -- null = uses budget_bucket
  spacing_ms      int not null default 1000,
  budget_bucket   text,                                   -- shared bucket (e.g. 'wikimedia'); null = source id
  hosts           text[] not null default '{}',
  robots_required boolean not null default true,          -- unkeyed web path/undocumented endpoint => honour robots.txt
  backfill_fn     text                                    -- edge fn that serves mode 'backfill' for this source
);

create table if not exists ripples.att_channel_map (
  category text not null,
  channel  text not null,
  relevant boolean not null default true,
  primary key (category, channel)
);

-- ---------- topic registry ----------
create table if not exists ripples.att_topics (
  topic_id    bigserial primary key,
  qid         text unique,
  label_key   text unique,                                -- 'lang:Title' or 'source:item_id'
  label       text not null,
  title_en    text,
  lang        text not null default 'en',
  category    text,
  status      text not null default 'active' check (status in ('active','panel','dormant','retired')),
  in_panel    boolean not null default false,             -- frozen placebo panel membership (survives status changes)
  origin      text not null check (origin in ('trend','hop','panel','manual','cascade')),
  first_seen  date not null default current_date,
  last_active date,
  meta        jsonb not null default '{}'::jsonb,         -- {"p31":[..],"median_views":n,"decile":d,"resolved":"wikidata|miss"}
  check (qid is not null or label_key is not null)
);
create index if not exists att_topics_status_idx on ripples.att_topics (status);
create index if not exists att_topics_panel_idx on ripples.att_topics (in_panel) where in_panel;

create table if not exists ripples.att_series (
  series_id  bigserial primary key,
  source     text not null references ripples.att_sources(source) on delete cascade,
  metric     text not null default 'n',
  geo        text not null default 'ALL',
  key        text not null,
  topic_id   bigint references ripples.att_topics(topic_id) on delete set null,
  created_at timestamptz not null default now(),
  last_day   date,
  unique (source, metric, geo, key)
);
create index if not exists att_series_topic_idx on ripples.att_series (topic_id);

create table if not exists ripples.att_keys (
  topic_id   bigint not null references ripples.att_topics(topic_id) on delete cascade,
  source     text not null references ripples.att_sources(source) on delete cascade,
  metric     text not null default 'n',
  geo        text not null default 'ALL',
  key        text not null,
  key_type   text not null check (key_type in
               ('term','hashtag','title','qid','ticker','repo','package','appid','model','media','domain','market','place','sector','warning')),
  match      jsonb not null default '{}'::jsonb,
  weight     real not null default 1.0,
  verified   boolean not null default false,
  enabled    boolean not null default true,
  created_by text not null default 'auto' check (created_by in ('auto','manual','llm')),
  series_id  bigint references ripples.att_series(series_id) on delete set null,
  primary key (topic_id, source, metric, geo, key)
);
create index if not exists att_keys_source_idx on ripples.att_keys (source, key);

create table if not exists ripples.att_qid_map (
  wiki  text not null,
  title text not null,
  qid   text not null,
  primary key (wiki, title)
);
create index if not exists att_qid_map_qid_idx on ripples.att_qid_map (qid);

create table if not exists ripples.att_label_cache (
  label_norm  text not null,
  lang        text not null default 'en',
  qid         text,
  label_key   text,
  method      text not null,
  confidence  real,
  resolved_at timestamptz not null default now(),
  primary key (label_norm, lang)
);
create index if not exists att_label_cache_trgm on ripples.att_label_cache using gin (label_norm extensions.gin_trgm_ops);

-- ---------- observations ----------
create table if not exists ripples.attention_obs (
  series_id bigint not null references ripples.att_series(series_id) on delete cascade,
  day       date   not null,
  value     double precision not null,
  aux       real,
  meta      jsonb,
  primary key (series_id, day)
) with (fillfactor = 90);

create table if not exists ripples.attention_obs_hourly (
  series_id bigint not null references ripples.att_series(series_id) on delete cascade,
  ts        timestamptz not null,
  value     double precision not null,
  aux       real,
  primary key (series_id, ts)
);

create or replace view ripples.attention_obs_v with (security_invoker = true) as
  select s.source, s.metric, s.geo, s.key, o.day, o.value, o.aux, o.meta, s.topic_id, s.series_id
  from ripples.attention_obs o join ripples.att_series s using (series_id);

-- ---------- edges ----------
create table if not exists ripples.att_edges (
  source     text not null references ripples.att_sources(source) on delete cascade,
  geo        text not null default 'ALL',
  from_key   text not null,
  to_key     text not null,
  period     date not null,
  grain      text not null check (grain in ('day','month')),
  n          double precision not null,
  lift       real,
  pmi        real,
  from_topic bigint references ripples.att_topics(topic_id) on delete set null,
  to_topic   bigint references ripples.att_topics(topic_id) on delete set null,
  meta       jsonb,
  primary key (source, geo, from_key, to_key, period, grain)
);
create index if not exists att_edges_from_idx on ripples.att_edges (from_topic, period);

-- ---------- discovery ----------
create table if not exists ripples.att_trend_candidates (
  day         date not null,
  source      text not null references ripples.att_sources(source) on delete cascade,
  geo         text not null default 'ALL',
  label       text not null,
  rank        int,
  value       double precision,
  evidence    real not null check (evidence between 0 and 1),
  qid         text,
  topic_id    bigint references ripples.att_topics(topic_id) on delete set null,
  observed_at timestamptz not null default now(),
  meta        jsonb,
  primary key (day, source, geo, label)
);

create table if not exists ripples.att_trends (
  day       date not null,
  topic_id  bigint not null references ripples.att_topics(topic_id) on delete cascade,
  qid       text,
  a_score   real,
  d_score   real not null,
  t_score   real not null,
  breadth   smallint not null,
  channels  text[] not null,
  sources   text[] not null,
  geos      int not null default 0,
  onset     date,
  rank      smallint not null,
  primary key (day, topic_id)
);

-- ---------- scores ----------
create table if not exists ripples.att_series_z (
  day       date not null,
  series_id bigint not null references ripples.att_series(series_id) on delete cascade,
  z         real, zstar real, ratio real, kappa real, n_base smallint,
  method    text check (method in ('robust','negbin','rank','uncalibrated')),
  primary key (day, series_id)
);

create table if not exists ripples.att_channel_scores (
  day      date not null,
  topic_id bigint not null references ripples.att_topics(topic_id) on delete cascade,
  channel  text not null,
  z_c      real, z_std real, weight real,
  members  jsonb,
  primary key (day, topic_id, channel)
);

create table if not exists ripples.att_index (
  day          date not null,
  topic_id     bigint not null references ripples.att_topics(topic_id) on delete cascade,
  a_score      real,
  n_channels   smallint,
  n_channels_3 smallint,
  completeness real,
  dims         jsonb,
  primary key (day, topic_id)
);

-- ---------- null model ----------
create table if not exists ripples.att_calibration (
  source text not null references ripples.att_sources(source) on delete cascade,
  as_of  date not null,
  n      int not null,
  knots_z real[] not null,
  knots_p real[] not null,
  tail_q real, tail_beta real,
  sd_null_channel jsonb,
  primary key (source, as_of)
);
create table if not exists ripples.att_weekday (
  source text not null, geo text not null default 'ALL',
  dow smallint not null check (dow between 0 and 6),
  holiday text not null default '',
  effect real not null,
  as_of date not null,
  primary key (source, geo, dow, holiday)
);
create table if not exists ripples.att_channel_corr (
  as_of date primary key,
  channels text[] not null,
  r real[][] not null,
  sd_null jsonb not null
);
create table if not exists ripples.att_lag_windows (
  channel text not null, event_type text not null check (event_type in ('breaking','organic','any')),
  l_days real not null, n int not null, as_of date not null,
  primary key (channel, event_type)
);

-- ---------- hops ----------
create table if not exists ripples.att_hop_candidates (
  as_of       date not null,
  u_topic     bigint not null references ripples.att_topics(topic_id) on delete cascade,
  v_topic     bigint not null references ripples.att_topics(topic_id) on delete cascade,
  proposed_by text[] not null,
  n_families  smallint generated always as (cardinality(proposed_by)::smallint) stored,
  edge        jsonb not null,
  status      text not null default 'queued' check (status in
                ('queued','waiting_series','testing','tested','exploratory','skipped')),
  primary key (as_of, u_topic, v_topic)
);

create table if not exists ripples.att_hop_tests (
  as_of        date not null,
  u_topic      bigint not null,
  v_topic      bigint not null,
  t_u          date not null,
  t_v          date,
  lag_days     real,
  onsets       jsonb,
  t_stat       real,
  n_channels_3 smallint,
  ratio        real,
  pass_timing  boolean, pass_agree boolean, pass_link boolean,
  link_kind    text check (link_kind in ('measured','structural','comention','tv','newsroom','search','none')),
  p_topic      real, n_topic int,
  p_date       real, n_date  int,
  p_link       real, n_link  int,
  fluke        real,
  q            real,
  verdict      text check (verdict in ('confirmed','probable','rejected','reversed','common_cause','exploratory')),
  detail       jsonb,
  primary key (as_of, u_topic, v_topic),
  foreign key (as_of, u_topic, v_topic) references ripples.att_hop_candidates(as_of, u_topic, v_topic) on delete cascade
);

create table if not exists ripples.att_placebo_draws (
  as_of date not null, u_topic bigint not null, v_topic bigint not null,
  kind  text not null check (kind in ('topic','date','link')),
  draw  int not null,
  ref   text not null,
  pass  boolean not null, t_stat real,
  primary key (as_of, u_topic, v_topic, kind, draw)
);

-- ---------- operations ----------
create table if not exists ripples.att_state (
  k text primary key, v jsonb not null, updated_at timestamptz not null default now()
);

create table if not exists ripples.att_budget (
  bucket text not null,
  day    date not null default current_date,
  used   int  not null default 0,
  cap    int  not null,
  primary key (bucket, day)
);

create table if not exists ripples.att_jobs (
  id          bigserial primary key,
  kind        text not null check (kind in ('backfill','ensure_series','test','placebo','resolve')),
  fn          text,
  payload     jsonb not null,
  priority    smallint not null default 5,
  status      text not null default 'queued' check (status in ('queued','running','done','failed','skipped')),
  attempts    smallint not null default 0,
  not_before  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  started_at  timestamptz, finished_at timestamptz,
  error       text,
  dedupe_key  text,
  http_req    bigint,
  batch_key   text                                  -- jobs with equal fn+batch_key may be merged into one dispatch
);
create index if not exists att_jobs_q_idx on ripples.att_jobs (status, priority, not_before);
create unique index if not exists att_jobs_dedupe_idx on ripples.att_jobs (dedupe_key)
  where status in ('queued','running') and dedupe_key is not null;

create table if not exists ripples.att_runs (
  run_id      bigserial primary key,
  fn          text not null, mode text not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  ok          boolean, partial boolean,
  requests    int, rows_upserted int,
  http        jsonb,
  error       text, detail jsonb
);
create index if not exists att_runs_fn_idx on ripples.att_runs (fn, started_at desc);

-- ---------- seed: sources (ATTENTION_STACK §1 ship-now + §2 add-later; RED sources never inserted) ----------
insert into ripples.att_sources
 (source, family, channel, grade, value_kind, grain, history_from, quality, enabled, reason, needs_secret, policy_d1, tier,
  attribution, license_note, per_run_cap, per_day_cap, spacing_ms, budget_bucket, hosts, robots_required, backfill_fn)
values
 -- Tier 1
 ('wiki.pv','wikipedia','reading','green','count','day','2015-07-01',1,true,null,null,false,'ship',
  'Pageviews: Wikimedia Foundation (CC0)','CC0; follow the Wikimedia UA policy',500,null,100,'wikimedia','{wikimedia.org}',false,'att-wiki'),
 ('wiki.cs','wikipedia','reading','green','count','month','2017-11-01',1,true,null,null,false,'ship',
  'Clickstream: Wikimedia Foundation (CC0)','CC0',3,3,1000,null,'{dumps.wikimedia.org}',false,null),
 ('gdelt.gkg','gdelt','news','green','share','hour','2015-02-18',1,true,null,null,false,'ship',
  'Data: The GDELT Project (gdeltproject.org)','Cite GDELT and link gdeltproject.org. Raw files only (DOC API is RED from our IP)',1,96,0,null,'{data.gdeltproject.org}',true,null),
 ('hn.algolia','hn','social','green','share','day','2007-02-19',1,true,null,null,false,'ship',
  'Hacker News counts via the HN Search API by Algolia','Official API; counts only',1500,4000,50,null,'{hn.algolia.com}',true,'att-social'),
 ('se.api','stackexchange','social','yellow','share','day','2008-08-01',1,true,'unkeyed quota (300/day) until an SE app key exists',null,false,'ship',
  'Stack Exchange network (CC BY-SA)','CC BY-SA attribution; commercial scale needs a data licence',250,300,100,null,'{api.stackexchange.com}',true,'att-social'),
 ('finra.shvol','finra','money','yellow','count','day','2020-01-02',1,true,null,null,false,'ship',
  'FINRA Reg SHO daily short sale volume files','Check FINRA redistribution terms; publish only z and ratios, never volumes',25,251,1000,null,'{cdn.finra.org}',true,'att-market'),
 ('wiki.topcc','wikipedia','reading','green','rank','day','2021-01-01',1,true,null,null,false,'ship',
  'Pageviews: Wikimedia Foundation (CC0)','Do not try to recover rows hidden by the privacy threshold',60,null,100,'wikimedia','{wikimedia.org}',false,null),
 ('npm.dl','npm','builder','green','count','day','2015-01-10',1,true,null,null,false,'ship',
  'npm download counts (api.npmjs.org)','Official API',200,400,200,null,'{api.npmjs.org}',true,'att-charts'),
 ('gh.search','github','builder','green','rank','day',null,1,true,'unauthenticated quota until github_token exists',null,false,'ship',
  'GitHub REST API','Official API; register a token for 30 searches/min',8,8,6500,null,'{api.github.com}',true,null),
 ('gh.stars','github','builder','green','count','day','2011-02-12',1,true,'unauthenticated quota until github_token exists',null,false,'ship',
  'GitHub REST API / GH Archive','Official API',50,50,1000,null,'{api.github.com}',true,'att-charts'),
 ('anilist','anilist','consumption','yellow','count','day','2014-01-01',1,true,null,null,false,'ship',
  'AniList','Free for non-commercial use; contact AniList before charging',50,150,2100,null,'{graphql.anilist.co}',true,'att-charts'),
 ('tsa.pax','tsa','physical','green','level','day','2019-01-01',1,true,null,null,false,'ship',
  'TSA checkpoint travel numbers','Public domain',3,3,1000,null,'{www.tsa.gov}',true,'att-world'),
 ('mta.ridership','mta','physical','green','level','day','2020-03-01',1,true,null,null,false,'ship',
  'MTA daily ridership via NY Open Data','NY Open Data terms',3,3,1000,null,'{data.ny.gov}',true,'att-world'),
 ('usgs.eq','usgs','physical','green','count','day','1970-01-01',1,true,null,null,false,'ship',
  'U.S. Geological Survey earthquake catalog (ComCat, DYFI)','Public domain',3,3,1000,null,'{earthquake.usgs.gov}',true,'att-world'),
 ('iem.warn','iem','physical','green','count','day','2005-01-01',1,true,null,null,false,'ship',
  'Iowa Environmental Mesonet, Iowa State University','At most 1 request per 10 s',3,3,10000,null,'{mesonet.agron.iastate.edu}',true,'att-world'),
 ('fema.decl','fema','institutional','green','count','day','1953-05-02',1,true,null,null,false,'ship',
  'This product uses the FEMA OpenFEMA API, but is not endorsed by FEMA. The Federal Government or FEMA cannot vouch for the data or analyses derived from these data after the data have been retrieved from the Agency''s website(s).',
  'Must display the OpenFEMA non-endorsement notice',3,3,1000,null,'{www.fema.gov}',true,'att-world'),
 ('hiringlab.postings','hiringlab','institutional','green','index','day','2020-02-01',1,true,null,null,false,'ship',
  'Indeed Hiring Lab job postings index (CC BY 4.0)','CC BY 4.0; credit "Indeed Hiring Lab"',3,3,1000,null,'{raw.githubusercontent.com,api.github.com}',true,'att-world'),
 ('sec.efts','edgar','institutional','green','count','month','2001-01-01',1,false,'needs owner contact email',null,false,'ship',
  'U.S. SEC EDGAR full-text search','SEC fair-access policy requires a contact email in the User-Agent; at most 10 req/s',200,200,500,null,'{efts.sec.gov}',true,'att-market'),
 ('usasp.spend','usaspending','institutional','green','level','month','2008-01-01',1,true,null,null,false,'ship',
  'USAspending.gov','Public domain',50,50,1000,null,'{api.usaspending.gov}',true,'att-market'),
 ('wiki.media','wikipedia','reading','green','count','day','2015-07-01',1,true,null,null,false,'ship',
  'Mediarequests: Wikimedia Foundation (CC0)','CC0',200,null,100,'wikimedia','{wikimedia.org}',false,null),
 ('tranco.rank','tranco','consumption','yellow','rank','day','2019-01-01',1,true,null,null,false,'ship',
  'Tranco list (Le Pochat et al., NDSS 2019)','List download only; /api is disallowed by robots.txt',1,1,0,null,'{tranco-list.eu}',true,null),
 -- Tier 2 (warm-up)
 ('bsky.jet','bluesky','social','green','share','hour',null,1,true,null,null,false,'ship',
  'Bluesky (AT Protocol) via Jetstream','Open protocol; counts and distinct-DID sketches only; honour deletes',1,288,0,null,'{jetstream1.us-east.bsky.network,jetstream2.us-east.bsky.network}',true,null),
 ('ia.thirdeye','tv','tv','yellow','share','hour',null,1,true,null,null,false,'ship',
  'Internet Archive TV News Archive (Third Eye)','Ask the Internet Archive before charging',1,24,0,null,'{archive.org}',true,null),
 ('gt.rss','google_trends','search','yellow','bucket','hour',null,1,true,'collected by ripples-collect (mode trends)',null,false,'ship',
  'Source: Google Trends','RSS only; never in paid features or open data',8,192,1000,null,'{trends.google.com}',true,null),
 ('poly.mkt','polymarket','money','yellow','level','day',null,1,true,null,null,false,'ship',
  'Polymarket','No redistribution licence; publish only derived z',220,220,500,null,'{gamma-api.polymarket.com,clob.polymarket.com}',true,null),
 ('kalshi.mkt','kalshi','money','yellow','level','day',null,1,true,null,null,false,'ship',
  'Kalshi','Ask Kalshi about market-data licensing',300,300,200,null,'{api.elections.kalshi.com}',true,null),
 ('news.sitemap','news_sitemaps','news','yellow','count','day',null,1,true,'AP skipped (Cloudflare)',null,false,'ship',
  'Publisher news sitemaps: BBC, NYT, The Guardian, Fox News','robots.txt allows; counts only',4,16,2000,null,'{www.bbc.com,www.nytimes.com,www.theguardian.com,www.foxnews.com}',true,null),
 ('apple.rss','apple_charts','consumption','yellow','rank','day',null,1,true,null,null,false,'ship',
  'Apple Marketing Tools RSS feeds','Marketing feed; game only; Appfigures for paid features',25,25,3000,null,'{rss.marketingtools.apple.com,rss.applemarketingtools.com}',true,null),
 ('steamspy','steam','consumption','yellow','level','day',null,1,true,null,null,false,'ship',
  'SteamSpy','At most 1 request/s',5,5,1100,null,'{steamspy.com}',true,null),
 ('hf.trending','huggingface','builder','green','index','day',null,1,true,null,null,false,'ship',
  'Hugging Face Hub API','Official API',100,100,300,null,'{huggingface.co}',true,null),
 ('masto.tags','mastodon','social','yellow','count','day',null,0.5,true,null,null,false,'ship',
  'Mastodon (mastodon.social and one non-English instance)','Check each instance''s terms; tie-breaker weight 0.5',250,750,400,null,'{mastodon.social}',true,null),
 ('masto.trends','mastodon','social','yellow','rank','day',null,0.5,true,null,null,false,'ship',
  'Mastodon trends','Check each instance''s terms',10,30,400,null,'{mastodon.social}',true,null),
 ('bsky.trends','bluesky','social','yellow','count','hour',null,1,true,'unspecced endpoint: no paid feature may depend on it',null,false,'ship',
  'Bluesky trending topics','Unspecced endpoint',2,48,1000,null,'{public.api.bsky.app}',true,null),
 ('ol.trending','openlibrary','consumption','green','rank','day',null,1,true,null,null,false,'ship',
  'Open Library (Internet Archive)','Official API',5,5,1000,null,'{openlibrary.org}',true,null),
 ('gdacs','gdacs','physical','green','level','day',null,1,true,null,null,false,'ship',
  'GDACS, European Commission Joint Research Centre','Credit EC JRC',3,3,1000,null,'{www.gdacs.org}',true,null),
 ('citibike.trips','citibike','physical','green','level','day','2013-06-01',1,true,null,null,false,'ship',
  'Citi Bike System Data','Citi Bike Data License Agreement; no use of its trademarks',3,3,1000,null,'{s3.amazonaws.com}',true,null),
 ('pypi.dl','pypi','builder','yellow','count','day',null,1,true,'community-run pypistats (180 d history)',null,false,'ship',
  'pypistats.org','Community-run; move to the BigQuery PyPI dataset before charging',30,30,1000,null,'{pypistats.org}',true,'att-charts'),
 -- §2a free keys / policy (disabled until the owner acts)
 ('mediacloud','mediacloud','news','yellow','count','day','2008-01-01',1,false,'needs owner key (Media Cloud research key)','mediacloud_key',false,'key','Media Cloud','Research key terms',null,null,1000,null,'{search.mediacloud.org}',false,null),
 ('gt.alpha','google_trends','search','yellow','index','day','2021-01-01',1,false,'needs owner key (Google Trends API alpha)','gtrends_alpha_key',false,'key','Source: Google Trends','Alpha terms must allow commercial use',null,null,1000,null,'{trends.googleapis.com}',false,null),
 ('guardian.api','guardian','news','yellow','count','day','1999-01-01',1,false,'needs owner key (Guardian Open Platform)','guardian_key',false,'key','Powered by the Guardian','Non-commercial key',null,null,1000,null,'{content.guardianapis.com}',false,null),
 ('nyt.api','nyt','news','yellow','count','day','1851-01-01',1,false,'needs owner key (NYT developer)','nyt_key',false,'key','Data provided by The New York Times','Non-commercial key',null,null,6000,null,'{api.nytimes.com}',false,null),
 ('podcastindex','podcastindex','consumption','green','count','day',null,1,false,'needs owner key (Podcast Index)','podcastindex_key',false,'key','Podcast Index','Key terms',null,null,1000,null,'{api.podcastindex.org}',false,null),
 ('yt.api','youtube','consumption','yellow','count','day',null,1,false,'needs owner key (YouTube Data API v3); 30-day storage rule','youtube_key',false,'key','YouTube','Refresh or delete stored stats within 30 days; keep derived z only',null,null,1000,null,'{www.googleapis.com}',false,null),
 ('bing.wm','bing','search','yellow','count','week',null,1,false,'needs owner key (Bing Webmaster, internal use only)','bing_wm_key',false,'key','Microsoft Bing Webmaster Tools','Internal use only',null,null,1000,null,'{ssl.bing.com}',false,null),
 ('pinterest.trends','pinterest','search','yellow','index','week',null,1,false,'needs owner app approval (Pinterest API v5)','pinterest_token',false,'key','Pinterest Trends','Commercial use needs approval',null,null,1000,null,'{api.pinterest.com}',false,null),
 ('twitch.helix','twitch','consumption','yellow','level','day',null,1,false,'needs owner key + policy D1 sign-off','twitch_client',true,'policy','Twitch','ORANGE*: developer agreement',null,null,1000,null,'{api.twitch.tv}',false,null),
 ('tmdb.trending','tmdb','consumption','yellow','rank','day',null,1,false,'needs owner key (TMDB)','tmdb_key',false,'key','This product uses the TMDB API but is not endorsed or certified by TMDB','Non-commercial key',null,null,1000,null,'{api.themoviedb.org}',false,null),
 ('steam.api','steam','consumption','yellow','level','day',null,1,false,'needs owner key + policy D1 sign-off','steam_key',true,'policy','Steam Web API','ORANGE*: personal-use free tier',null,null,1000,null,'{api.steampowered.com}',false,null),
 ('coingecko','coingecko','money','yellow','rank','day',null,1,false,'needs owner key + policy D1 sign-off (no keyless calls)','coingecko_key',true,'policy','Data provided by CoinGecko','ORANGE*',null,null,2000,null,'{api.coingecko.com}',false,null),
 ('twelvedata','twelvedata','money','yellow','level','day',null,1,false,'needs owner key + policy D1 sign-off (no demo-key calls)','twelvedata_key',true,'policy','Twelve Data','ORANGE*; free tier is personal use',null,null,8000,null,'{api.twelvedata.com}',false,null),
 ('alphavantage','alphavantage','money','yellow','level','day','2000-01-01',1,false,'needs owner key + policy D1 sign-off','alphavantage_key',true,'policy','Alpha Vantage','ORANGE*; free tier is personal use',null,null,15000,null,'{www.alphavantage.co}',false,null),
 ('wiki.eventstreams','wikipedia','reading','green','count','hour',null,1,false,'GREEN per DEMARCATION §7.1 lead decision; no collector built yet',null,false,'ship','Wikimedia EventStreams (CC0)','Serial, honest UA, no retry after 429/503',null,null,0,null,'{stream.wikimedia.org}',false,null),
 ('nws.alerts','nws','physical','yellow','count','day',null,1,false,'api.weather.gov robots.txt disallows; ORANGE* pending owner D1 (IEM covers it)',null,true,'policy','National Weather Service','Public domain; needs contact in UA',null,null,1000,null,'{api.weather.gov}',true,null),
 ('netflix.top10','netflix','consumption','yellow','level','week','2021-06-28',1,false,'manual weekly TSV upload to Storage att-manual/netflix/ by the owner',null,false,'manual','Netflix Top 10','Human download only (hole type 4)',null,null,0,null,'{}',true,null),
 -- §2b paid licences (disabled)
 ('dfs.trends','dataforseo','search','yellow','index','day','2004-01-01',1,false,'paid: DataForSEO Google Trends (~$16/mo), owner approval + key','dataforseo_login',false,'paid','Google Trends data via DataForSEO','Reseller; check Google v. SerpApi before depending on it',null,null,1000,null,'{api.dataforseo.com}',false,null),
 ('dfs.ac','dataforseo','search','yellow','rank','day',null,1,false,'paid: DataForSEO Autocomplete (~$5/mo), owner approval + key','dataforseo_login',false,'paid','Autocomplete via DataForSEO','Replaces RED direct suggest calls',null,null,1000,null,'{api.dataforseo.com}',false,null),
 ('dfs.amazon','dataforseo','search','yellow','count','month',null,1,false,'paid: DataForSEO Labs Amazon volumes, owner approval + key','dataforseo_login',false,'paid','Amazon search volume via DataForSEO','Vendor provenance risk',null,null,1000,null,'{api.dataforseo.com}',false,null),
 ('brave.suggest','brave','search','green','rank','day',null,1,false,'paid: Brave Search/Suggest API contract','brave_key',false,'paid','Brave Search API','Contract terms',null,null,1000,null,'{api.search.brave.com}',false,null),
 ('glimpse','glimpse','search','green','level','week',null,1,false,'paid: Glimpse enterprise contract','glimpse_key',false,'paid','Glimpse','Contract terms',null,null,1000,null,'{}',false,null),
 ('x.api','x','social','yellow','count','day',null,1,false,'paid: X API tier decision ($200-$5k/mo)','x_bearer',false,'paid','X','Licensed replacement for RED trends24/getdaytrends',null,null,1000,null,'{api.x.com}',false,null),
 ('tiktok.vendor','tiktok','social','yellow','count','day',null,1,false,'paid: enterprise social listening vendor (Creative Center is RED)',null,false,'paid','TikTok via licensed vendor','Enterprise contract',null,null,1000,null,'{}',false,null),
 ('reddit.api','reddit','social','yellow','count','day',null,1,false,'paid: Reddit Data API commercial contract (free tier non-commercial; .json is RED)','reddit_contract',false,'paid','Reddit','Commercial contract',null,null,1000,null,'{oauth.reddit.com}',false,null),
 ('wme.realtime','wikipedia','reading','green','count','hour',null,1,false,'paid: Wikimedia Enterprise contract',null,false,'paid','Wikimedia Enterprise','Contract terms',null,null,1000,null,'{}',false,null),
 ('eventregistry','eventregistry','news','yellow','count','day',null,1,false,'paid: Event Registry / NewsAPI.ai (replaces RED Google News RSS)','eventregistry_key',false,'paid','Event Registry','Contract terms',null,null,1000,null,'{eventregistry.org}',false,null),
 ('gdelt.bq','gdelt','news','green','count','day','2015-02-18',1,false,'paid: GDELT on BigQuery (bytes scanned)','gcp_sa',false,'paid','Data: The GDELT Project','Cite GDELT',null,null,1000,null,'{}',false,null),
 ('apple.music','apple_music','consumption','yellow','rank','day',null,1,false,'paid: Apple Developer Program ($99/yr) for Apple Music API','apple_music_key',false,'paid','Apple Music','Replaces RED Spotify/Billboard/Shazam backends',null,null,1000,null,'{api.music.apple.com}',false,null),
 ('appfigures','appfigures','consumption','green','rank','day',null,1,false,'paid: Appfigures (replaces Apple RSS for paid use)','appfigures_key',false,'paid','Appfigures','Contract terms',null,null,1000,null,'{api.appfigures.com}',false,null),
 ('polygon','polygon','money','yellow','level','day',null,1,false,'paid: equities data licence before any paid ticker feature','polygon_key',false,'paid','Polygon.io','Contract terms',null,null,1000,null,'{api.polygon.io}',false,null),
 ('flightaware','flightaware','physical','yellow','level','day',null,1,false,'paid: FlightAware AeroAPI / Cirium (OpenSky is non-commercial)','flightaware_key',false,'paid','FlightAware','Contract terms',null,null,1000,null,'{aeroapi.flightaware.com}',false,null),
 ('similarweb','similarweb','consumption','yellow','rank','day',null,1,false,'paid: Similarweb (Cloudflare Radar is CC BY-NC)','similarweb_key',false,'paid','Similarweb','Contract terms',null,null,1000,null,'{}',false,null),
 ('card.spend','card_spend','money','yellow','level','day',null,1,false,'paid: Consumer Edge / Facteus / Earnest',null,false,'paid','Card spending panel','Contract terms',null,null,1000,null,'{}',false,null)
on conflict (source) do nothing;

-- ---------- security: service-only ----------
do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'ripples' and c.relkind = 'r'
             and (c.relname like 'att\_%' or c.relname in ('attention_obs','attention_obs_hourly'))
  loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on table ripples.%I from anon, authenticated, public', t);
  end loop;
end $$;
revoke all on ripples.attention_obs_v from anon, authenticated, public;
do $$ declare s text; begin
  for s in select sequence_name from information_schema.sequences where sequence_schema = 'ripples'
           and (sequence_name like 'att\_%' ) loop
    execute format('revoke all on sequence ripples.%I from anon, authenticated, public', s);
  end loop;
end $$;
