-- Knock-On v5 / W2: migration ripples_v5_pipeline
-- Pipeline internals (SPEC §10 "W2 tables") plus the few helper tables the pipeline needs.
-- Everything lives in schema ripples (not exposed to PostgREST): RLS on, no policies, revoked from
-- anon/authenticated/public. Safe to run before or after W1 (create ... if not exists).
create schema if not exists ripples;
revoke all on schema ripples from public, anon, authenticated;
grant usage on schema ripples to service_role;

-- Resolved Wikipedia/Wikidata articles (one row per QID, enwiki title).
create table if not exists ripples.articles (
  qid           text primary key check (qid ~ '^Q[0-9]+$'),
  title_en      text not null,
  category      text check (category is null or category in ('person','place','film_tv','music','sport','science_health',
                  'tech','business','politics_law','food_drink','nature_weather','history_culture','other')),
  emoji         text,
  short_desc    text,
  p31           text[] not null default '{}',
  date_of_death date,
  is_disambig   boolean not null default false,
  is_list       boolean not null default false,
  sensitive     boolean not null default false,   -- natural disaster / harmful weather: Board only, neutral copy
  blocked       boolean not null default false,   -- never a seed, option or Call It article
  block_reason  text,
  is_human      boolean not null default false,
  sitelinks     int,
  updated_at    timestamptz not null default now()
);
create index if not exists articles_title on ripples.articles (title_en);

-- title (any language, or a search query) -> QID / enwiki title. status: ok | missing | no_en | no_match
create table if not exists ripples.title_map (
  lang        text not null,          -- 'en', 'de', ... ; queries use 'q:<lang>'
  title       text not null,          -- as seen in the source (spaces, not underscores)
  qid         text,
  title_en    text,
  status      text not null check (status in ('ok','missing','no_en','no_match')),
  resolved_at timestamptz not null default now(),
  primary key (lang, title)
);
create index if not exists title_map_qid on ripples.title_map (qid);

-- Wikidata class (P31 value) -> one of the 13 categories, plus safety flags (block / sensitive).
create table if not exists ripples.category_map (
  class_qid  text primary key check (class_qid ~ '^Q[0-9]+$'),
  category   text not null check (category in ('person','place','film_tv','music','sport','science_health','tech',
               'business','politics_law','food_drink','nature_weather','history_culture','other')),
  label      text,
  parents    text[] not null default '{}',     -- P279 (subclass of)
  flag       text check (flag is null or flag in ('block','sensitive')),
  flag_reason text,
  source     text not null default 'auto' check (source in ('seed','auto','manual')),
  updated_at timestamptz not null default now()
);

-- Deterministic safety filter (SPEC §5.4): an article QID, a class QID (matched against P31 and its P279 parents)
-- or a case-insensitive title regex. action 'sensitive' = Board only.
create table if not exists ripples.blocklist (
  id            bigserial primary key,
  qid           text check (qid is null or qid ~ '^Q[0-9]+$'),
  title_pattern text,
  reason        text not null,
  action        text not null default 'block' check (action in ('block','sensitive')),
  check (qid is not null or title_pattern is not null)
);
create unique index if not exists blocklist_uq on ripples.blocklist (coalesce(qid,''), coalesce(title_pattern,''));

-- Seed-source observations: Google Trends RSS, Bluesky getTrends, Wikimedia top-per-country, per-project top,
-- featured feed (tfa / mostread / news / onthisday / dyk).
create table if not exists ripples.trend_obs (
  id          bigserial primary key,
  observed_at timestamptz not null default now(),
  day         date not null,                -- the data day the row describes (UTC)
  source      text not null check (source in ('gtrends','bsky','topcountry','wikitop','featured')),
  geo         text,                         -- country / language / featured section
  lang        text,                         -- wiki language of `query` for Wikipedia titles; RSS geo language for gtrends
  query       text not null,                -- search query / Bluesky topic / article title (spaces)
  traffic     int,
  rank        int,
  news        jsonb,                        -- gtrends RSS news items [{title,source,url}]
  qid         text
);
create index if not exists trend_obs_day on ripples.trend_obs (day, source);
create index if not exists trend_obs_qid on ripples.trend_obs (qid);
create unique index if not exists trend_obs_wiki_uq on ripples.trend_obs (day, source, geo, query)
  where source in ('topcountry','wikitop','featured');

create table if not exists ripples.runs (
  as_of       date primary key,
  kind        text not null default 'live' check (kind in ('live','practice')),
  stage       text not null default 'collect_daily'
                check (stage in ('collect_daily','resolve','screen','seeds','expand','build','done','delayed','failed')),
  stage_at    timestamptz not null default now(),
  wm_calls    int not null default 0,
  errors      int not null default 0,
  detail      jsonb not null default '{}',
  started_at  timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists ripples.jobs (
  id           bigserial primary key,
  as_of        date not null,
  kind         text not null check (kind in ('collect','resolve','screen','expand','history','split','refresh')),
  role         text check (role is null or role in ('real','decoy','board','callit')),
  root_qid     text,
  parent_qid   text,
  parent_title text,
  parent_onset date,
  depth        int,
  payload      jsonb not null default '{}',
  status       text not null default 'queued' check (status in ('queued','running','done','failed','skipped')),
  attempts     int not null default 0,
  calls        int not null default 0,
  error        text,
  result       jsonb,
  net_id       bigint,
  created_at   timestamptz not null default now(),
  started_at   timestamptz,
  finished_at  timestamptz
);
create index if not exists jobs_asof on ripples.jobs (as_of, status);
create index if not exists jobs_status on ripples.jobs (status) where status in ('queued','running');

-- Screening series (130 days) for every shortlisted seed-source article: seed onset test + decoy-epicenter pool.
create table if not exists ripples.screen (
  as_of         date not null,
  qid           text not null,
  title         text not null,
  median_views  numeric,          -- e^m - 1 at the onset baseline (or the as_of baseline when no onset)
  onset         date,
  z_peak        numeric,
  peak_multiple numeric,
  peak_day      date,
  max_abs_z14   numeric,          -- max |z| over [as_of-13, as_of] (baseline for as_of-13)
  base_from     date,
  base_to       date,
  spark         int[],            -- last 90 days, oldest first
  primary key (as_of, qid)
);

create table if not exists ripples.seeds (
  as_of                 date not null,
  qid                   text not null,
  role                  text not null check (role in ('real','decoy')),
  title                 text,
  onset                 date,
  peak_multiple         numeric,
  z_peak                numeric,
  median_views          numeric,
  langs                 int,
  sources               text[],
  biggest_in_days       int,
  biggest_since_records boolean,
  spark                 int[],
  baseline              jsonb,
  matched_to            text,
  rank                  int,
  primary key (as_of, qid, role)
);

create table if not exists ripples.candidates (
  as_of          date not null,
  role           text not null check (role in ('real','decoy')),
  root_qid       text not null,
  depth          int not null,
  parent_qid     text not null,
  qid            text not null,
  title          text,
  cs_rank        int,
  cs_clicks      int,
  set_rank       int,             -- position in the fixed candidate set (clickstream first, then outlinks by median)
  linked         boolean not null default true,
  median_views   numeric,
  s_stat         numeric,
  onset_lag      int,
  multiple       numeric,
  p_time         numeric,
  n_placebo      int,
  pass_raw       boolean not null default false,
  calm           boolean not null default false,
  max_abs_z      numeric,
  split_ok       boolean,
  mult_desktop   numeric,
  mult_mobile    numeric,
  main_page      boolean not null default false,
  shared_trigger boolean not null default false,
  category       text,
  spark          int[],           -- 90 days, only for pass_raw or calm rows
  job_id         bigint,
  primary key (as_of, role, root_qid, parent_qid, qid)
);
create index if not exists candidates_qid on ripples.candidates (as_of, qid);

create table if not exists ripples.fluke_rates (
  as_of          date not null,
  sbin           text not null check (sbin in ('3-4','4-6','6-10','10+')),
  real_tested    int not null,    -- pooled over the trailing 90 days (all depths)
  real_pass      int not null,
  decoy_tested   int not null,
  decoy_pass     int not null,
  fluke          numeric,         -- min(1, (decoy_pass/decoy_tested)/(real_pass/real_tested)); null if undefined
  d_real_tested  int not null default 0,   -- this as_of's own counts (the pooled sums read these)
  d_real_pass    int not null default 0,
  d_decoy_tested int not null default 0,
  d_decoy_pass   int not null default 0,
  primary key (as_of, sbin)
);

create table if not exists ripples.chains (
  id         bigserial primary key,
  as_of      date not null,
  kind       text,
  root_qid   text,
  rounds     jsonb not null,
  score      numeric,
  detail     jsonb,
  used_n     int,
  created_at timestamptz not null default now()
);
create index if not exists chains_asof on ripples.chains (as_of);

do $$
declare t text;
begin
  foreach t in array array['articles','title_map','category_map','blocklist','trend_obs','runs','jobs','screen','seeds',
                           'candidates','fluke_rates','chains'] loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on table ripples.%I from anon, authenticated, public', t);
  end loop;
end $$;
revoke all on all sequences in schema ripples from anon, authenticated, public;

-- Pipeline config (W1 owns the table; these keys are W2's). Existing values are never overwritten.
insert into ripples.config (key, value) values
  ('wm_daily_cap',          '6000'),
  ('callit_climatology',    '0.08'),
  ('callit_cs_mult',        '{"top5":1.0,"top20":1.0,"none":1.0}'),
  ('callit_window_offset',  '0'),
  ('pipeline',              '{"max_running_aqs":2,"max_running_api":1,"dispatch_per_tick":6,"aqs_concurrency":4,
                              "screen_titles":240,"screen_per_job":80,"resolve_titles_per_job":150,"resolve_queries_per_job":40,
                              "resolve_max_titles":1500,"resolve_max_queries":160,"expand_prefilter_calls":14,
                              "candidate_cap":60,"min_outlink_median":300,"seeds_real":12,"seeds_decoy":8}'),
  ('gt_trending_now',       'false')
on conflict (key) do nothing;

-- Blocklist seed: SPEC §5.4 title patterns (+ a few event patterns). Patterns are written so that they behave the
-- same as a case-insensitive POSIX regex in Postgres (~*) and as a JavaScript RegExp with the "i" flag (the expand
-- function uses them to drop candidates before the 60 cap). Class QIDs are seeded by sql/03 after label verification.
insert into ripples.blocklist (qid, title_pattern, reason, action) values
  (null, '^(death|killing|murder|shooting|assassination|disappearance|kidnapping|abduction|lynching|execution|beheading|stabbing|rape) of', 'violence: death/killing of (SPEC 5.4)', 'block'),
  (null, 'massacre', 'violence: massacre (SPEC 5.4)', 'block'),
  (null, 'attack', 'violence: attack (SPEC 5.4)', 'block'),
  (null, 'bombing', 'violence: bombing (SPEC 5.4)', 'block'),
  (null, '(^|[^a-z])(shootings?|stabbings?|killings|murders|spree|genocide|pogrom|terrorism|terrorist|hostage|suicide|suicides)([^a-z]|$)', 'violence/terrorism/suicide words', 'block'),
  (null, '(^|[^a-z])war( |$|\))', 'war', 'block'),
  (null, '(^|[^a-z])(battle|siege|invasion|insurgency|uprising) of ', 'war/battle', 'block'),
  (null, '(^|[^a-z])(pornograph|sexual abuse|sexual assault|sex abuse|child abuse|incest|onlyfans)', 'sexual/adult', 'block'),
  (null, '^[0-9]{4}.*(crash|derailment|collapse|explosion|stampede|sinking|shipwreck|disaster|riots?)([^a-z]|$)', 'mass-casualty event', 'block'),
  (null, '(^|[^a-z])(earthquake|hurricane|typhoon|cyclone|tornado|tornadoes|floods?|flooding|wildfires?|bushfires?|tsunami|eruption|landslide|heat wave|heatwave|blizzard|tropical storm|storm [a-z]+)([^a-z]|$)', 'natural disaster / weather with harm (Board only)', 'sensitive')
on conflict do nothing;
