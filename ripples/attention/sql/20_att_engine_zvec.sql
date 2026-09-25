-- Migration: att_engine_zvec (WS-B, Ripple Map v6, 2026-09-25)
-- ENGINE_SPEC §3.1–3.5 and §10.1–10.2: additive columns, new engine tables, math helpers and the nightly att_zvec build.
-- Everything is service-only (RLS on, no grants). Nothing in public.* or the v4/v5 tables is touched.
-- Tables owned by WS-A (att_mech_edges, att_mech_templates, att_edge_priors, att_families, att_family_calendar,
-- att_family_events, att_channel_stat) are created here only `if not exists`, with the exact ENGINE §10.2 DDL, so the
-- engine compiles whichever workstream lands first. Seed rows use `on conflict do nothing` (WS-A's rows win).

create schema if not exists ripples;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Additive columns (ENGINE §10.1)
-- ---------------------------------------------------------------------------------------------------------------------
alter table ripples.att_hop_candidates
  add column if not exists hop_id      bigint generated always as identity,
  add column if not exists event_id    bigint,
  add column if not exists role        text not null default 'real',
  add column if not exists parent_hop  bigint,
  add column if not exists depth       smallint not null default 1,
  add column if not exists path        jsonb not null default '[]'::jsonb,
  add column if not exists path_type   text,
  add column if not exists prior       real,
  add column if not exists bh_weight   real,
  add column if not exists channels    text[],
  add column if not exists excluded_ch text[],
  add column if not exists window_close date,
  add column if not exists looks       date[],
  add column if not exists voi         real,
  add column if not exists frozen_hash text,
  add column if not exists node        text,            -- 'Q…' or 'source:geo:metric:key'
  add column if not exists onset       date,            -- t_p (parent onset) at freeze
  add column if not exists sign        smallint not null default 0,
  add column if not exists reconstructed boolean not null default false,
  add column if not exists frozen_at   timestamptz;

do $$ begin
  alter table ripples.att_hop_candidates drop constraint if exists att_hop_candidates_role_check;
  alter table ripples.att_hop_candidates add constraint att_hop_candidates_role_check
    check (role in ('real','decoy','library','fork_check','negative_control','positive_control'));
  -- the old PK (as_of,u_topic,v_topic) allowed one path per target; ENGINE §2.1 allows up to 3 paths per target.
  if exists (select 1 from pg_constraint where conname = 'att_hop_candidates_pkey'
             and conrelid = 'ripples.att_hop_candidates'::regclass
             and pg_get_constraintdef(oid) like 'PRIMARY KEY (as_of, u_topic, v_topic)') then
    alter table ripples.att_hop_tests drop constraint if exists att_hop_tests_as_of_u_topic_v_topic_fkey;
    alter table ripples.att_hop_candidates drop constraint att_hop_candidates_pkey;
    alter table ripples.att_hop_candidates add primary key (hop_id);
    create index if not exists att_hop_candidates_uv_idx on ripples.att_hop_candidates (as_of, u_topic, v_topic);
  end if;
end $$;
create index if not exists att_hop_candidates_event_idx on ripples.att_hop_candidates (event_id);
create index if not exists att_hop_candidates_day_idx on ripples.att_hop_candidates (as_of, role);

alter table ripples.att_hop_tests
  add column if not exists hop_id bigint, add column if not exists look_no smallint, add column if not exists is_final boolean default false,
  add column if not exists stat_kind text, add column if not exists s_by_channel jsonb,
  add column if not exists s_pre real, add column if not exists common_shock boolean, add column if not exists attribution jsonb,
  add column if not exists loso_ok boolean, add column if not exists linkage jsonb, add column if not exists q_w real,
  add column if not exists f_bin text, add column if not exists f real,
  add column if not exists h_score real, add column if not exists h_bin smallint, add column if not exists tier text,
  add column if not exists tier_reason text, add column if not exists rho_shrunk real, add column if not exists rho_lo real,
  add column if not exists rho_hi real, add column if not exists rho_raw real,
  add column if not exists replication jsonb,
  add column if not exists retracted_at timestamptz, add column if not exists retract_reason text, add column if not exists ledger_seq bigint,
  add column if not exists look_day date, add column if not exists n_families smallint, add column if not exists provisional boolean default false,
  add column if not exists attention_only boolean default false, add column if not exists reversed boolean default false,
  add column if not exists lag_ok boolean, add column if not exists frozen_att jsonb, add column if not exists p_floor real,
  add column if not exists placebo jsonb, add column if not exists flags text[] not null default '{}';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'att_hop_tests_tier_check') then
    alter table ripples.att_hop_tests add constraint att_hop_tests_tier_check
      check (tier is null or tier in ('measured','likely','watching','flat','retracted'));
  end if;
  if exists (select 1 from pg_constraint where conname = 'att_hop_tests_pkey' and conrelid = 'ripples.att_hop_tests'::regclass
             and pg_get_constraintdef(oid) like 'PRIMARY KEY (as_of, u_topic, v_topic)') then
    alter table ripples.att_hop_tests drop constraint att_hop_tests_pkey;
    update ripples.att_hop_tests set look_no = 1 where look_no is null;
    alter table ripples.att_hop_tests alter column look_no set not null;
    alter table ripples.att_hop_tests alter column look_no set default 1;
    alter table ripples.att_hop_tests add primary key (hop_id, look_no);
    -- keep the old key as a (non-unique: several paths per target) index for the P-WIKI write-back
    create index if not exists att_hop_tests_uv_idx on ripples.att_hop_tests (as_of, u_topic, v_topic);
  end if;
end $$;
create index if not exists att_hop_tests_day_idx on ripples.att_hop_tests (as_of);

alter table ripples.att_placebo_draws
  add column if not exists hop_id bigint, add column if not exists look_no smallint, add column if not exists t_h real;
do $$ begin
  if exists (select 1 from pg_constraint where conname = 'att_placebo_draws_pkey' and conrelid = 'ripples.att_placebo_draws'::regclass
             and pg_get_constraintdef(oid) like 'PRIMARY KEY (as_of, u_topic, v_topic, kind, draw)') then
    alter table ripples.att_placebo_draws drop constraint att_placebo_draws_pkey;
    update ripples.att_placebo_draws set look_no = 1 where look_no is null;
    alter table ripples.att_placebo_draws alter column look_no set not null;
    alter table ripples.att_placebo_draws alter column hop_id set not null;
    alter table ripples.att_placebo_draws add primary key (hop_id, look_no, kind, draw);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. New tables (ENGINE §10.2). WS-A-owned tables are `if not exists`.
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_zvec (
  series_id bigint primary key references ripples.att_series on delete cascade,
  from_day  date not null,                  -- day of ar[1] (daily) or the first period start (weekly/monthly)
  grain     text not null default 'day' check (grain in ('day','week','month')),
  n         int not null,                   -- array length
  ar        real[] not null,                -- abnormal response (z − c_t), null where missing
  resid     real[] not null,                -- x̃_t − ŷ_t (log units for count/share/level/index; raw for rate)
  ar_agg    real[],                         -- aggregate-demeaned AR (regional series), null otherwise
  sigma     real not null,                  -- σ on the last day (ENGINE §10.2 stores σ as a scalar; the rolling σ_t array was dropped for the storage budget)
  trend_b   real, phi real, kappa real,
  demean    text not null default 'panel' check (demean in ('panel','aggregate','none')),
  agg_series bigint,
  value_kind text not null,
  base_level real,                          -- median x over the last 91 observed days (deciles for topic placebos)
  lam        real,                          -- λ̂ = med(n_B) on the last day (count sources)
  n_obs      int not null default 0,        -- observed days in the array
  n_obs_90   int not null default 0,        -- observed days in the last 90
  same_dow   boolean not null default false,
  refreshed timestamptz not null default now()
);
-- storage budget (ENGINE §9): the undemeaned z and the rolling σ_t arrays are not stored; raw z is reconstructed from att_zvec_ct
alter table ripples.att_zvec drop column if exists zraw, drop column if exists sig;

create table if not exists ripples.att_channel_stat (
  channel text primary key, kind text not null check (kind in ('attention','outcome')),
  stat_kind text not null check (stat_kind in ('peak','car','release')),
  l_days smallint not null, sided text not null default 'signed', min_kappa_measured real not null default 0.5
);

create table if not exists ripples.att_mech_edges (
  edge_id bigserial primary key,
  from_node text not null, to_node text not null,
  etype text not null check (etype in ('MAP','WD','MECH','CS','GK','IO')),
  prop text, template text, sign smallint not null default 0, strength real not null default 1,
  meta jsonb not null default '{}',
  version text not null, valid_from date not null default current_date, valid_to date,
  unique (from_node, to_node, etype, coalesce(prop,''), coalesce(template,''), version)
);
create index if not exists att_mech_edges_from_idx on ripples.att_mech_edges (from_node, etype) where valid_to is null;

create table if not exists ripples.att_mech_templates (
  template text primary key, family text not null, target_pattern jsonb not null,
  sign smallint not null, channel text not null, l_days smallint, rationale text not null, version text not null
);

create table if not exists ripples.att_edge_priors (
  etype text not null, channel text not null, family text not null default 'any',
  tested int not null default 0, measured int not null default 0, prior real not null,
  seeded boolean not null default true, fitted_to date, version text not null,
  primary key (etype, channel, family, version)
);

create table if not exists ripples.att_families (
  family text primary key, label text not null, scheduled boolean not null default false,
  mapper jsonb not null
);
create table if not exists ripples.att_family_calendar (
  id bigserial primary key, family text references ripples.att_families, label text not null, qid text,
  scheduled_for date not null, registered_at timestamptz not null default now(), ledger_seq bigint
);
create table if not exists ripples.att_events (
  event_id bigserial primary key, as_of date not null, topic_id bigint references ripples.att_topics,
  qid text, label text not null, family text not null references ripples.att_families,
  role text not null check (role in ('real','decoy','library','positive_control')),
  onset date not null, magnitude real, sensitive boolean not null default false,
  matched_to bigint, slug text unique, reconstructed boolean not null default false,
  status text not null default 'running' check (status in ('running','ended','nowhere','archived')),
  unique (as_of, topic_id, role)
);
create index if not exists att_events_onset_idx on ripples.att_events (onset, role);
create table if not exists ripples.att_family_events (
  event_id bigint primary key references ripples.att_events, family text not null, onset date not null,
  magnitude real, in_prior_set boolean not null, in_replication_set boolean not null
);
create table if not exists ripples.att_replication (
  as_of date not null, family text not null, edge_class text not null, channel text not null,
  n int not null, hits int not null, p_dose real, route text, q_family real, one_off boolean default false,
  primary key (as_of, family, edge_class, channel)
);
create table if not exists ripples.att_cascades (
  event_id bigint primary key references ripples.att_events,
  version int not null default 0, payload jsonb not null,
  denominators jsonb not null, weakest_tier text, sum_f real, updated_at timestamptz not null default now(),
  payload_hash text
);
create table if not exists ripples.att_cascade_versions (
  event_id bigint not null, version int not null, payload jsonb not null, payload_hash text not null,
  published_at timestamptz not null default now(), primary key (event_id, version)
);
create table if not exists ripples.att_controls (
  id bigserial primary key, kind text not null check (kind in ('positive','negative','spikein')),
  spec jsonb not null, last_run date, passed boolean, detail jsonb
);
create table if not exists ripples.att_calibration_public (
  as_of date primary key, payload jsonb not null
);
create table if not exists ripples.att_ledger (
  seq bigserial primary key, day date not null, kind text not null check (kind in
    ('freeze','register','resolve','retract','calibration','breaker','model_version','control','version_publish')),
  ref jsonb not null, payload_hash text not null, prev_hash text not null, chain_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists att_ledger_day_idx on ripples.att_ledger (day, kind);

-- engine-internal tables (WS-B)
create table if not exists ripples.att_engine_source_map (   -- source → engine channel / kind / value kind / aggregate key
  source text primary key references ripples.att_sources(source) on delete cascade,
  channel text not null, value_kind text not null check (value_kind in ('count','share','rank','index','level','rate')),
  same_dow boolean not null default false,        -- PHYS/ECON daily: same-weekday baseline + same-weekday year-ago term
  agg_key text,                                   -- key of the aggregate series for regional demeaning (same source/metric)
  domain text not null,                           -- one of the 8 public domain codes
  metric_kinds jsonb not null default '{}'::jsonb -- per-metric value_kind overrides, e.g. {"p":"rate","vol24h":"count"}
);
create table if not exists ripples.att_holidays (day date primary key, code text not null);   -- generated from att_holiday_rule below
create table if not exists ripples.att_common_days (         -- common_shock day flags (ENGINE §3.5)
  day date primary key, sources text[] not null default '{}', c_by_source jsonb not null default '{}'::jsonb,
  reason text not null default 'panel', as_of date not null default current_date
);
create table if not exists ripples.att_node_series (         -- a node's measurement bundle
  node text not null, series_id bigint not null references ripples.att_series on delete cascade,
  channel text not null, primary key (node, series_id)
);
create index if not exists att_node_series_series_idx on ripples.att_node_series (series_id);
create table if not exists ripples.att_family_classes (      -- P31 class → family (deterministic, ENGINE §1.3)
  class_qid text primary key, family text not null, note text
);
create table if not exists ripples.att_sd_null (             -- cached null sd of the window statistic per series/window
  series_id bigint not null references ripples.att_series on delete cascade,
  stat_kind text not null, w_len smallint not null, sided text not null,
  sd real not null, n int not null, as_of date not null,
  primary key (series_id, stat_kind, w_len, sided)
);
-- c_t per (source, day) from the *undemeaned* z, kept in a small table so demeaning is reproducible and the flags are auditable
create table if not exists ripples.att_zvec_ct (source text not null, day date not null, c real not null, n_panel int not null, primary key (source, day));

create table if not exists ripples.att_breaker (             -- circuit breaker state per (path type × channel) cell
  cell text primary key, days_over int not null default 0, tripped_at date, restored_at date, days_under int not null default 0,
  last_rate real, last_lo real, last_hi real, ks_bad_weeks int not null default 0, updated_at timestamptz not null default now()
);
create table if not exists ripples.att_fluke_bins (          -- decoy-calibrated f per bin, refreshed by att_finalize
  as_of date not null, s_bin text not null, h_bin smallint not null,   -- h_bin 0 = pooled (H stratification dropped)
  decoy_pass int not null, decoy_tested int not null, real_pass int not null, real_tested int not null,
  f real, warming boolean not null default true, primary key (as_of, s_bin, h_bin)
);
create table if not exists ripples.att_hop_registry (        -- ENGINE §5.6.6 forward track record (one row per hop)
  hop_id bigint primary key references ripples.att_hop_candidates(hop_id) on delete cascade,
  registered_at timestamptz not null default now(), window_close date not null, p_hat real not null,
  family text not null, path_type text not null, channel text not null, ledger_seq bigint,
  resolved_at timestamptz, hit boolean, final_tier text, published_tier text, published_at timestamptz,
  frozen_att jsonb
);

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Seeds: channel table (ENGINE §1.1 / §7), source map, family classes, seed priors (ENGINE §2.1)
-- ---------------------------------------------------------------------------------------------------------------------
insert into ripples.att_channel_stat(channel, kind, stat_kind, l_days, sided, min_kappa_measured) values
  ('READ','attention','peak',3,'signed',0.5), ('SRCH','attention','peak',3,'signed',0.5), ('SOC','attention','peak',2,'signed',0.5),
  ('NEWS','attention','peak',2,'signed',0.5), ('TV','attention','peak',2,'signed',0.5),
  ('PM','outcome','peak',4,'signed',0.5), ('BLD','outcome','car',14,'signed',0.5), ('CONS','outcome','car',14,'signed',0.5),
  ('PHYS','outcome','car',7,'signed',0.5), ('JOBS','outcome','release',28,'signed',0.5), ('INST','outcome','car',90,'signed',0.5),
  ('ECON','outcome','peak',4,'signed',0.5), ('MONEY','outcome','peak',4,'signed',0.5)
on conflict (channel) do nothing;

-- MONEY is disabled: att_freeze_candidates never proposes MONEY series and att_test_hop refuses them (ENGINE §0, §1.1).
insert into ripples.att_engine_source_map(source, channel, value_kind, same_dow, agg_key, domain, metric_kinds)
select s.source, m.channel, m.value_kind, m.same_dow, m.agg_key, m.domain, m.metric_kinds::jsonb
from (values
  ('wiki.pv','READ','count',false,null,'reading','{}'), ('wiki.topcc','READ','rank',false,null,'reading','{}'),
  ('wiki.media','READ','count',false,null,'reading','{}'), ('gt.rss','SRCH','index',false,null,'search','{}'), ('gt.alpha','SRCH','index',false,null,'search','{}'),
  ('hn.algolia','SOC','share',false,null,'social','{}'), ('se.api','SOC','share',false,null,'social','{}'),
  ('masto.tags','SOC','count',false,null,'social','{}'), ('masto.trends','SOC','rank',false,null,'social','{}'), ('bsky.jet','SOC','share',false,null,'social','{}'),
  ('bsky.trends','SOC','count',false,null,'social','{}'),
  ('gdelt.gkg','NEWS','share',false,null,'news','{}'), ('news.sitemap','NEWS','count',false,null,'news','{}'), ('ia.thirdeye','TV','share',false,null,'news','{}'),
  ('poly.mkt','PM','rate',false,null,'markets','{"p":"rate","vol24h":"count"}'), ('kalshi.mkt','PM','rate',false,null,'markets','{"p":"rate","vol24h":"count"}'),
  ('npm.dl','BLD','count',false,null,'builders','{}'), ('pypi.dl','BLD','count',false,null,'builders','{}'),
  ('gh.stars','BLD','count',false,null,'builders','{}'), ('gh.search','BLD','rank',false,null,'builders','{}'), ('hf.trending','BLD','index',false,null,'builders','{}'),
  ('anilist','CONS','count',false,null,'consumption','{}'), ('apple.rss','CONS','rank',false,null,'consumption','{}'),
  ('steamspy','CONS','level',false,null,'consumption','{}'), ('ol.trending','CONS','rank',false,null,'consumption','{}'), ('tranco.rank','CONS','rank',false,null,'consumption','{}'),
  ('tsa.pax','PHYS','level',true,null,'real_world','{}'), ('mta.ridership','PHYS','level',true,null,'real_world','{}'),
  ('citibike.trips','PHYS','level',true,null,'real_world','{}'), ('usgs.eq','PHYS','count',false,null,'real_world','{}'),
  ('gdacs','PHYS','level',false,null,'real_world','{}'), ('eia.930','PHYS','level',true,'US48','real_world','{}'),
  ('hiringlab.postings','JOBS','index',false,'__total__','jobs','{}'), ('dol.claims','JOBS','level',false,'US','jobs','{}'),
  ('bls.ces','JOBS','level',false,null,'jobs','{}'),
  ('fema.decl','INST','count',false,null,'institutions','{}'), ('iem.warn','INST','count',false,null,'institutions','{}'),
  ('usasp.spend','INST','level',false,null,'institutions','{}'), ('sec.efts','INST','count',false,null,'institutions','{}'),
  ('fred','ECON','rate',true,null,'economy','{}'), ('eia.prices','ECON','level',true,null,'economy','{}'), ('bls.cpi_items','ECON','level',false,null,'economy','{}'),
  ('finra.shvol','MONEY','count',false,null,'markets','{}'), ('twelvedata','MONEY','level',false,null,'markets','{}'),
  ('alphavantage','MONEY','level',false,null,'markets','{}'), ('polygon','MONEY','level',false,null,'markets','{}'), ('coingecko','MONEY','rank',false,null,'markets','{}')
) as m(source, channel, value_kind, same_dow, agg_key, domain, metric_kinds)
join ripples.att_sources s on s.source = m.source
on conflict (source) do nothing;

insert into ripples.att_family_classes(class_qid, family, note) values
  ('Q8092','hazard.storm','tropical cyclone'), ('Q7944','hazard.quake','earthquake'), ('Q8068','hazard.flood','flood'),
  ('Q169950','hazard.wildfire','wildfire'), ('Q11424','media.film','film'), ('Q7889','media.game','video game'),
  ('Q5398426','media.series','television series'), ('Q5','person','human')
on conflict (class_qid) do nothing;

-- Seed prior table (ENGINE §2.1). version '6.0' is hashed into the model_version ledger row (25_att_engine_ledger.sql).
insert into ripples.att_edge_priors(etype, channel, family, prior, seeded, version)
select e, c, 'any', p, true, '6.0'
from (values ('MAP',0.20::real),('MECH',0.25),('WD',0.10),('WIKI',0.15),('CS',0.15),('GK',0.10)) as x(e,p)
cross join (select channel c from ripples.att_channel_stat) ch
on conflict do nothing;

insert into ripples.att_config(key, value) values
  ('engine', '{"method":"6.0","prior_cutoff":"2026-01-01","pi_min":0.05,"caps":{"P-MAP":25,"P-MECH":10,"P-WD":15,"P-WIKI":15,"P-COM":10,"event":60},
               "date_draws":200,"date_draws_top":2000,"top_n":100,"link_draws":200,"topic_draws":300,"bc_stop":10,
               "min_family_draws":30,"q_measured":0.05,"q_likely":0.20,"q_provisional":0.01,"q_demote":0.10,
               "tau2_prior":4,"loso_min_t":3,"hard_cap_tests":1600,"zvec_days":420,"zvec_days_long":2555}')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Math helpers (immutable, pure SQL/plpgsql; no Python anywhere in the engine)
-- ---------------------------------------------------------------------------------------------------------------------
-- Φ(z): Abramowitz–Stegun 26.2.17, |error| < 7.5e-8
create or replace function ripples.att_norm_cdf(z float8) returns float8
language sql immutable strict set search_path = '' as $$
  select case when z >= 0 then 1 - q.p else q.p end
  from (select (0.3989422804014327 * exp(-z*z/2.0)) *
               (s.t*(0.319381530 + s.t*(-0.356563782 + s.t*(1.781477937 + s.t*(-1.821255978 + s.t*1.330274429))))) as p
        from (select 1.0/(1.0 + 0.2316419*abs(z)) as t) s) q
$$;

-- Φ⁻¹(p): Acklam's algorithm (rel. error ~1.15e-9), p clamped to [1e-12, 1-1e-12]
create or replace function ripples.att_norm_inv(p_in float8) returns float8
language plpgsql immutable strict set search_path = '' as $$
declare p float8 := least(greatest(p_in, 1e-12), 1 - 1e-12); q float8; r float8; x float8;
  a1 constant float8 := -3.969683028665376e+01; a2 constant float8 := 2.209460984245205e+02; a3 constant float8 := -2.759285104469687e+02;
  a4 constant float8 := 1.383577518672690e+02; a5 constant float8 := -3.066479806614716e+01; a6 constant float8 := 2.506628277459239e+00;
  b1 constant float8 := -5.447609879822406e+01; b2 constant float8 := 1.615858368580409e+02; b3 constant float8 := -1.556989798598866e+02;
  b4 constant float8 := 6.680131188771972e+01; b5 constant float8 := -1.328068155288572e+01;
  c1 constant float8 := -7.784894002430293e-03; c2 constant float8 := -3.223964580411365e-01; c3 constant float8 := -2.400758277161838e+00;
  c4 constant float8 := -2.549732539343734e+00; c5 constant float8 := 4.374664141464968e+00; c6 constant float8 := 2.938163982698783e+00;
  d1 constant float8 := 7.784695709041462e-03; d2 constant float8 := 3.224671290700398e-01; d3 constant float8 := 2.445134137142996e+00;
  d4 constant float8 := 3.754408661907416e+00; plow constant float8 := 0.02425;
begin
  if p < plow then
    q := sqrt(-2*ln(p));
    x := (((((c1*q+c2)*q+c3)*q+c4)*q+c5)*q+c6) / ((((d1*q+d2)*q+d3)*q+d4)*q+1);
  elsif p <= 1 - plow then
    q := p - 0.5; r := q*q;
    x := (((((a1*r+a2)*r+a3)*r+a4)*r+a5)*r+a6)*q / (((((b1*r+b2)*r+b3)*r+b4)*r+b5)*r+1);
  else
    q := sqrt(-2*ln(1-p));
    x := -(((((c1*q+c2)*q+c3)*q+c4)*q+c5)*q+c6) / ((((d1*q+d2)*q+d3)*q+d4)*q+1);
  end if;
  return x;
end $$;

-- Negative-binomial (r = null → Poisson) mid-p upper tail: p = P(N > n) + ½P(N = n); returns z = Φ⁻¹(1 − p) (AS §6.1.5).
-- The pmf recursion stops once it underflows past the mode (the remaining tail mass is negligible).
create or replace function ripples.att_nb_midp_z(n float8, mu float8, r float8) returns float8
language plpgsql immutable set search_path = '' as $$
declare k int := 0; pk float8; cum float8 := 0; nn int := greatest(0, floor(n))::int; p float8; lim int; early boolean := false;
begin
  if mu is null or mu <= 0 then return null; end if;
  if r is not null and r <= 0 then r := null; end if;
  if r is null then pk := exp(-mu); else pk := power(r/(r+mu), r); end if;
  lim := least(nn, 20000);
  while k < lim loop
    cum := cum + pk;
    if r is null then pk := pk * mu/(k+1); else pk := pk * ((k + r)/(k + 1.0)) * (mu/(r+mu)); end if;
    k := k + 1;
    if pk < 1e-280 and k > mu then early := true; exit; end if;
  end loop;
  p := case when early then 1 - cum else 1 - cum - pk/2.0 end;
  p := least(greatest(p, 1e-12), 1 - 1e-12);
  return ripples.att_norm_inv(1 - p);
end $$;

-- Easter Sunday (Gregorian, Anonymous algorithm)
create or replace function ripples.att_easter(y int) returns date
language sql immutable strict set search_path = '' as $$
  select make_date(y, (h + l - 7*m + 114)/31, ((h + l - 7*m + 114) % 31) + 1)
  from (select a, b, c, d, e, f, g, h, i, k, l, (a + 11*h + 22*l)/451 m
        from (select a, b, c, d, e, f, g, h, i, k, (32 + 2*e + 2*i - h - k) % 7 l
              from (select a, b, c, d, e, f, g, h, c/4 i, c % 4 k
                    from (select a, b, c, d, e, f, g, (19*a + b - d - g + 15) % 30 h
                          from (select y % 19 a, y/100 b, y % 100 c, (y/100)/4 d, (y/100) % 4 e, (y/100 + 8)/25 f, (y/100 - (y/100 + 8)/25 + 1)/3 g) q0) q1) q2) q3) q4
$$;

-- Holiday code for a day ('' when none): US federal (observed), UK bank holidays, Christmas/New Year week (ENGINE §3.2).
-- att_holiday_rule is the rule; att_holidays is generated from it once (2012–2031) and att_holiday is the fast lookup.
create or replace function ripples.att_holiday_rule(d date) returns text
language plpgsql immutable strict set search_path = '' as $$
declare y int := extract(year from d)::int; m int := extract(month from d)::int; dd int := extract(day from d)::int;
        dow int := extract(dow from d)::int; e date; obs date;
begin
  if (m = 12 and dd >= 24) or (m = 1 and dd <= 1) then return 'xmas_week'; end if;
  foreach obs in array array[make_date(y,1,1), make_date(y,6,19), make_date(y,7,4), make_date(y,11,11), make_date(y,12,25)] loop
    if d = obs or (extract(dow from obs) = 6 and d = obs - 1) or (extract(dow from obs) = 0 and d = obs + 1) then
      return case obs when make_date(y,1,1) then 'us_newyear' when make_date(y,6,19) then 'us_juneteenth'
                      when make_date(y,7,4) then 'us_july4' when make_date(y,11,11) then 'us_veterans' else 'us_xmas' end;
    end if;
  end loop;
  if m = 1 and dow = 1 and dd between 15 and 21 then return 'us_mlk'; end if;
  if m = 2 and dow = 1 and dd between 15 and 21 then return 'us_presidents'; end if;
  if m = 5 and dow = 1 and dd >= 25 then return 'us_memorial'; end if;
  if m = 9 and dow = 1 and dd <= 7 then return 'us_labor'; end if;
  if m = 10 and dow = 1 and dd between 8 and 14 then return 'us_columbus'; end if;
  if m = 11 and dow = 4 and dd between 22 and 28 then return 'us_thanksgiving'; end if;
  if m = 11 and dow = 5 and dd between 23 and 29 then return 'us_blackfriday'; end if;
  e := ripples.att_easter(y);
  if d = e - 2 then return 'uk_goodfriday'; end if;
  if d = e + 1 then return 'uk_eastermon'; end if;
  if m = 5 and dow = 1 and dd <= 7 then return 'uk_earlymay'; end if;
  if m = 8 and dow = 1 and dd >= 25 then return 'uk_summer'; end if;
  if m = 12 and dd = 26 then return 'uk_boxing'; end if;
  return '';
end $$;
insert into ripples.att_holidays(day, code)
select d::date, ripples.att_holiday_rule(d::date) from generate_series('2012-01-01'::date, '2031-12-31'::date, interval '1 day') d
where ripples.att_holiday_rule(d::date) <> ''
on conflict (day) do nothing;
create or replace function ripples.att_holiday(d date) returns text
language sql stable strict set search_path = '' as $$
  select coalesce((select code from ripples.att_holidays h where h.day = d), '')
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. att_zvec build (ENGINE §3.1–3.5)
-- ---------------------------------------------------------------------------------------------------------------------
-- Effective value kind of a series (source map + per-metric override; falls back to att_sources.value_kind)
create or replace function ripples.att_series_kind(p_series bigint) returns text
language sql stable set search_path = '' as $$
  select coalesce(m.metric_kinds ->> s.metric, m.value_kind, case when src.value_kind = 'bucket' then 'index' else src.value_kind end)
  from ripples.att_series s join ripples.att_sources src on src.source = s.source
  left join ripples.att_engine_source_map m on m.source = s.source
  where s.series_id = p_series
$$;

create or replace function ripples.att_series_channel(p_series bigint) returns text
language sql stable set search_path = '' as $$
  select coalesce(m.channel, case src.channel when 'reading' then 'READ' when 'search' then 'SRCH' when 'social' then 'SOC'
                                              when 'news' then 'NEWS' when 'tv' then 'TV' when 'money' then 'MONEY'
                                              when 'builder' then 'BLD' when 'consumption' then 'CONS' when 'physical' then 'PHYS'
                                              when 'institutional' then 'INST' end)
  from ripples.att_series s join ripples.att_sources src on src.source = s.source
  left join ripples.att_engine_source_map m on m.source = s.source
  where s.series_id = p_series
$$;

-- Pooled weekday and holiday effects per source (AS §6.1.2), written to att_weekday (geo 'ALL'; holiday '' = weekday rows)
create or replace function ripples.att_zvec_weekday(p_source text, p_day date) returns int
language plpgsql security definer set search_path = '' as $$
declare v_kind text; v_rows int := 0;
begin
  select coalesce(m.value_kind, s.value_kind) into v_kind
    from ripples.att_sources s left join ripples.att_engine_source_map m on m.source = s.source where s.source = p_source;
  create temp table if not exists _zw (series_id bigint, day date, x float8, h text) on commit drop;
  truncate _zw;
  insert into _zw
  select o.series_id, o.day,
         case v_kind when 'count' then ln(1 + greatest(o.value, 0)) when 'share' then ln((greatest(o.value,0) + 0.5) / nullif(t.value, 0) * 1e6)
                     when 'rank' then case when o.value between 1 and 100 then ln(101 - o.value) else 0 end
                     when 'index' then ln(1 + greatest(o.value, 0)) when 'level' then case when o.value > 0 then ln(o.value) end
                     else o.value end,
         coalesce(hd.code, '')
  from ripples.attention_obs o
  join ripples.att_series s on s.series_id = o.series_id
  left join ripples.att_series ts on v_kind = 'share' and ts.source = s.source and ts.metric = s.metric and ts.geo = s.geo and ts.key = '__total__'
  left join ripples.attention_obs t on t.series_id = ts.series_id and t.day = o.day
  left join ripples.att_holidays hd on hd.day = o.day
  where s.source = p_source and s.key <> '__total__' and o.day between p_day - 365 and p_day
    and (v_kind <> 'share' or t.value > 0);
  create index if not exists _zw_idx on _zw (series_id, day);
  analyze _zw;
  -- weekday effect: median residual against a centred 7-day median (pooled over the source's series, last 365 d)
  with r as (
    select a.series_id, a.day, a.x - (select percentile_cont(0.5) within group (order by b.x) from _zw b
                                        where b.series_id = a.series_id and b.day between a.day - 3 and a.day + 3) as res
    from _zw a where a.x is not null and a.h = ''),
  w as (select extract(dow from day)::int dow, percentile_cont(0.5) within group (order by res) eff, count(*) cnt from r group by 1)
  insert into ripples.att_weekday(source, geo, dow, holiday, effect, as_of)
  select p_source, 'ALL', w.dow, '', w.eff, p_day from w where w.cnt >= 20
  on conflict (source, geo, dow, holiday) do update set effect = excluded.effect, as_of = excluded.as_of;
  get diagnostics v_rows = row_count;
  -- holiday effect: residual against the centred 15-day median of non-holiday days; shrunk towards 0 with prior weight 8
  with r as (
    select a.series_id, a.day, a.h,
           a.x - (select percentile_cont(0.5) within group (order by b.x) from _zw b
                  where b.series_id = a.series_id and b.day between a.day - 7 and a.day + 7 and b.h = '') as res
    from _zw a where a.x is not null and a.h <> ''),
  hh as (select h, percentile_cont(0.5) within group (order by res) eff, count(*) cnt from r group by h)
  insert into ripples.att_weekday(source, geo, dow, holiday, effect, as_of)
  select p_source, 'ALL', 0, hh.h, hh.eff * hh.cnt / (hh.cnt + 8.0), p_day from hh where hh.cnt >= 3
  on conflict (source, geo, dow, holiday) do update set effect = excluded.effect, as_of = excluded.as_of;
  return v_rows;
end $$;

-- One daily series → one att_zvec row. p_phi is the (already shrunk) year-ago coefficient to apply (0 = none).
-- Returns {"sxy","sxx","n","nobs"}: year-ago sums so the driver can fit φ per source (robustly: trailing 3 years, |r| < 1, no holidays).
-- Deviations from ENGINE §3.3 recorded in the workstream report: Theil–Sen on same-weekday pairs 5–9 weeks apart on a weekly grid;
-- baseline days with < 28 (same-weekday: < 8) observed points get no z; the year-ago term is skipped on holidays.
create or replace function ripples.att_zvec_series(p_series bigint, p_day date, p_phi float8 default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s record; v_kind text; v_chan text; v_same boolean; v_n int; v_from date; v_first date; v_last date; v_nobs int;
  v_total bigint; v_agg bigint; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb);
  v_days int := coalesce((cfg->>'zvec_days')::int, 420); v_long int := coalesce((cfg->>'zvec_days_long')::int, 2555);
  v_ar real[]; v_res real[]; v_aragg real[]; v_sigma real; v_b real; v_kappa real; v_base real; v_lam real;
  v_sxy float8; v_sxx float8; v_np int; v_n90 int; v_beta float8; gpool float8[]; hpool jsonb; v_nb_all int; v_minb int;
begin
  select se.*, src.grain into s from ripples.att_series se join ripples.att_sources src on src.source = se.source where se.series_id = p_series;
  if not found then return null; end if;
  if s.grain not in ('day','hour') then return null; end if;
  v_kind := ripples.att_series_kind(p_series);
  v_chan := ripples.att_series_channel(p_series);
  select coalesce(m.same_dow, false) into v_same from ripples.att_engine_source_map m where m.source = s.source;
  v_same := coalesce(v_same, false);
  v_minb := case when v_same then 8 else 28 end;   -- same-weekday baselines hold ~13 points; 8 is the floor there
  select min(day), max(day), count(*) into v_first, v_last, v_nobs from ripples.attention_obs where series_id = p_series and day <= p_day;
  if v_nobs is null or v_nobs < 28 or v_last < p_day - 60 then return null; end if;
  v_n := case when v_first <= p_day - 1095 then v_long else v_days end;
  v_from := p_day - v_n + 1;
  if v_kind = 'share' and s.key <> '__total__' then
    select series_id into v_total from ripples.att_series t where t.source = s.source and t.metric = s.metric and t.geo = s.geo and t.key = '__total__';
  end if;
  if v_kind = 'share' and s.key = '__total__' then v_kind := 'count'; end if;
  select agg.series_id into v_agg
    from ripples.att_engine_source_map m join ripples.att_series agg on agg.source = s.source and agg.metric = s.metric and agg.key = m.agg_key
    where m.source = s.source and s.key <> m.agg_key limit 1;

  select array_agg(coalesce(w.effect, 0) order by d.dow) into gpool
    from generate_series(0, 6) d(dow) left join ripples.att_weekday w on w.source = s.source and w.geo = 'ALL' and w.dow = d.dow and w.holiday = '';
  select coalesce(jsonb_object_agg(holiday, effect), '{}'::jsonb) into hpool from ripples.att_weekday where source = s.source and geo = 'ALL' and holiday <> '';

  create temp table if not exists _zs (i int, day date, dow int, n float8, x float8, xt float8, m float8, yhat float8, sigma float8,
                                       lam float8, mu float8, var_n float8, nb int, z float8, r float8, h text, primary key (i)) on commit drop;
  truncate _zs;
  -- 1. transform over [from − 475, p_day] (475 = 364 year-ago + 111 baseline)
  insert into _zs(i, day, dow, n, x, h)
  select (g.day::date - v_from + 1), g.day::date, extract(dow from g.day)::int, o.value,
         case v_kind when 'count' then ln(1 + greatest(o.value, 0))
                     when 'share' then case when t.value > 0 then ln((greatest(o.value, 0) + 0.5) / t.value * 1e6) end
                     when 'rank' then case when o.value between 1 and 100 then ln(101 - o.value) else 0 end
                     when 'index' then ln(1 + greatest(o.value, 0))
                     when 'level' then case when o.value > 0 then ln(o.value) end
                     else o.value end,
         coalesce(hd.code, '')
  from generate_series(v_from - 475, p_day, interval '1 day') g(day)
  left join ripples.attention_obs o on o.series_id = p_series and o.day = g.day::date
  left join ripples.attention_obs t on v_total is not null and t.series_id = v_total and t.day = g.day::date
  left join ripples.att_holidays hd on hd.day = g.day::date;
  analyze _zs;

  -- 2. weekday (shrunk to pooled, prior weight 8) and holiday adjustment
  with own as materialized (
    select a.dow, count(*) m_k,
           percentile_cont(0.5) within group (order by a.x - (select percentile_cont(0.5) within group (order by b.x) from _zs b
                                                                  where b.i between a.i - 3 and a.i + 3 and b.x is not null)) g_hat
    from _zs a where a.x is not null and a.day > p_day - 365 and a.h = '' group by a.dow),
  gam as materialized (select d.dow, (coalesce(o.m_k, 0) * coalesce(o.g_hat, 0) + 8 * gpool[d.dow + 1]) / (coalesce(o.m_k, 0) + 8) g
          from generate_series(0, 6) d(dow) left join own o on o.dow = d.dow)
  update _zs z set xt = z.x - gam.g - coalesce((hpool ->> z.h)::float8, 0)
  from gam where gam.dow = z.dow and z.x is not null;

  -- 3. year-ago term: r_t = x̃_t − m_t (rolling baseline median; same-weekday for PHYS/ECON); φ̃ applied off holidays only
  update _zs z set r = z.xt - (select percentile_cont(0.5) within group (order by b.xt) from _zs b
                               where b.i between z.i - 111 and z.i - 21 and b.xt is not null and (not v_same or b.dow = z.dow))
  where z.xt is not null and z.i >= -363;
  select coalesce(sum(a.r * b.r), 0), coalesce(sum(b.r * b.r), 0), count(*) into v_sxy, v_sxx, v_np
    from _zs a join _zs b on b.i = a.i - 364
    where a.r is not null and b.r is not null and a.i >= greatest(1, v_n - 1095) and abs(a.r) < 1 and abs(b.r) < 1 and a.h = '' and b.h = '';
  if p_phi <> 0 and v_nobs >= 400 then
    update _zs z set xt = z.xt - p_phi * b.r from _zs b
     where b.i = z.i - 364 and b.r is not null and z.i >= 1 and z.xt is not null and z.h = '' and b.h = '' and abs(b.r) < 1;
  end if;

  -- 4. baseline stats per day t ≥ 1: B = [t−111, t−21] observed (same-weekday for PHYS/ECON); scale floors (ENGINE §3.4)
  update _zs z set m = q.m, lam = q.lam, mu = q.mu_n, var_n = q.var_n, nb = q.nb
  from (
    select a.i,
           percentile_cont(0.5) within group (order by b.xt) m,
           percentile_cont(0.5) within group (order by b.n) lam, avg(b.n) mu_n, var_samp(b.n) var_n, count(*) nb
    from _zs a
    join _zs b on b.i between a.i - 111 and a.i - 21 and b.xt is not null and (not v_same or b.dow = a.dow)
    where a.i >= 1
    group by a.i) q
  where q.i = z.i;
  update _zs set m = null where i >= 1 and coalesce(nb, 0) < v_minb;
  update _zs z set sigma = greatest(
      coalesce((select 1.4826 * percentile_cont(0.5) within group (order by abs(b.xt - z.m)) from _zs b
                where b.i between z.i - 111 and z.i - 21 and b.xt is not null and (not v_same or b.dow = z.dow)), 0),
      case when v_kind in ('count','share') then greatest(1 / sqrt(coalesce(z.lam, 0) + 1), 0.02)
           when v_kind = 'level' then 0.005 when v_kind = 'rate' then 0.01 else 0.02 end)
  where z.i >= 1 and z.m is not null;

  -- 5. growth: Theil–Sen restricted to same-weekday pairs 5–9 weeks apart inside B, on a weekly grid; applied only if |b|·60 > σ
  create temp table if not exists _zsl (i int primary key, b float8) on commit drop;
  truncate _zsl;
  insert into _zsl(i, b)
  select g.i, percentile_cont(0.5) within group (order by (b.xt - a.xt) / d.k)
  from (select i, dow from _zs where i >= 1 and m is not null and (v_n - i) % 7 = 0) g
  join _zs a on a.i between g.i - 111 and g.i - 21 and a.xt is not null and (not v_same or a.dow = g.dow)
  cross join (values (35),(42),(49),(56),(63)) d(k)
  join _zs b on b.i = a.i + d.k and b.i <= g.i - 21 and b.xt is not null
  group by g.i having count(*) >= 20;
  update _zs z set yhat = case when abs(sl.b) * 60 > z.sigma then z.m + sl.b * 66 else z.m end
  from (select z2.i, (select b from _zsl where _zsl.i <= z2.i order by _zsl.i desc limit 1) b from _zs z2 where z2.i >= 1) sl
  where sl.i = z.i and z.m is not null and sl.b is not null;
  update _zs set yhat = m where i >= 1 and yhat is null and m is not null;
  select b into v_b from _zsl order by i desc limit 1;

  -- 6. z: robust, or NB mid-p when a count source has λ̂ < 10
  update _zs z set z = case
      when z.xt is null or z.yhat is null then null
      when v_kind = 'count' and z.lam < 10 then
        ripples.att_nb_midp_z(z.n, z.mu * exp(z.yhat - z.m),
                              case when z.var_n > z.mu then (z.mu * z.mu) / (z.var_n - z.mu) end)
      else (z.xt - z.yhat) / z.sigma end
  where z.i >= 1;

  -- 7. arrays (index 1 = v_from). ar = raw z for now; panel demeaning (att_zvec_demean) sets ar = raw − c_t.
  select array_agg(z::real order by i), array_agg((xt - yhat)::real order by i)
    into v_ar, v_res from _zs where i >= 1;
  select sigma, lam into v_sigma, v_lam from _zs where i = v_n;
  if v_sigma is null then select sigma, lam into v_sigma, v_lam from _zs where i >= 1 and sigma is not null order by i desc limit 1; end if;
  if v_sigma is null then return null; end if;
  select count(*) into v_n90 from _zs where i > v_n - 90 and x is not null;
  select count(*) into v_nb_all from _zs where i between v_n - 111 and v_n - 21 and xt is not null;
  v_kappa := case when coalesce(v_nb_all, 0) < 28 then 0 else least(1, v_nb_all / 90.0) end;
  select percentile_cont(0.5) within group (order by x) into v_base from _zs where i > v_n - 91 and x is not null;

  -- 8. regional aggregate demeaning: β over the trailing 364 days of z against the aggregate's raw (undemeaned) z
  if v_agg is not null then
    select (sum(a.z * g.z) - count(*) * avg(a.z) * avg(g.z)) / nullif(sum(g.z * g.z) - count(*) * avg(g.z) * avg(g.z), 0)
      into v_beta
      from _zs a join (select zv.from_day + (u.o - 1)::int as day, u.z from ripples.att_zvec zv, unnest(ripples.att_zvec_rawz(zv.series_id)) with ordinality u(z, o) where zv.series_id = v_agg) g
        on g.day = a.day
      where a.i > v_n - 364 and a.z is not null and g.z is not null;
    if v_beta is not null then
      select array_agg((a.z - v_beta * g.z)::real order by a.i) into v_aragg
        from _zs a left join (select zv.from_day + (u.o - 1)::int as day, u.z from ripples.att_zvec zv, unnest(ripples.att_zvec_rawz(zv.series_id)) with ordinality u(z, o) where zv.series_id = v_agg) g
          on g.day = a.day where a.i >= 1;
    end if;
  end if;

  -- ar is written undemeaned (demean 'none' / 'aggregate'); att_zvec_demean subtracts c_t for panel sources afterwards
  insert into ripples.att_zvec(series_id, from_day, grain, n, ar, resid, ar_agg, sigma, trend_b, phi, kappa, demean, agg_series,
                               value_kind, base_level, lam, n_obs, n_obs_90, same_dow, refreshed)
  values (p_series, v_from, 'day', v_n, v_ar, v_res, v_aragg, v_sigma, v_b, p_phi, v_kappa,
          case when v_agg is not null and v_aragg is not null then 'aggregate' else 'none' end, v_agg,
          v_kind, v_base, v_lam, v_nobs, v_n90, v_same, clock_timestamp())
  on conflict (series_id) do update set from_day = excluded.from_day, grain = excluded.grain, n = excluded.n, ar = excluded.ar,
    resid = excluded.resid, ar_agg = excluded.ar_agg, sigma = excluded.sigma, trend_b = excluded.trend_b,
    phi = excluded.phi, kappa = excluded.kappa, demean = excluded.demean, agg_series = excluded.agg_series, value_kind = excluded.value_kind,
    base_level = excluded.base_level, lam = excluded.lam, n_obs = excluded.n_obs, n_obs_90 = excluded.n_obs_90, same_dow = excluded.same_dow,
    refreshed = clock_timestamp();
  return jsonb_build_object('sxy', v_sxy, 'sxx', v_sxx, 'n', v_np, 'nobs', v_nobs);
end $$;

-- Weekly / monthly series (ENGINE §3.2 last bullet): x̃ = ln y − μ_month-of-year − local linear trend (prior 36 months);
-- z = x̃ / (1.4826·MAD of residuals over the prior 36 months). One array element per period.
create or replace function ripples.att_zvec_series_periodic(p_series bigint, p_day date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s record; v_kind text; v_from date; v_n int; v_ar real[]; v_res real[]; v_sigma real; v_nobs int; v_kappa real; v_base real; v_w int;
begin
  select se.*, src.grain into s from ripples.att_series se join ripples.att_sources src on src.source = se.source where se.series_id = p_series;
  if not found or s.grain not in ('week','month') then return null; end if;
  v_kind := ripples.att_series_kind(p_series);
  v_w := case when s.grain = 'month' then 36 else 156 end;
  create temp table if not exists _zp (i int primary key, day date, x float8, xt float8, yhat float8, sigma float8, z float8) on commit drop;
  truncate _zp;
  if s.grain = 'month' then
    v_from := (date_trunc('month', p_day)::date - interval '119 months')::date; v_n := 120;
    insert into _zp(i, day, x)
    select g.i, (v_from + make_interval(months => g.i - 1))::date, case v_kind when 'level' then case when o.value > 0 then ln(o.value) end
                                                                        when 'count' then ln(1 + greatest(o.value, 0)) when 'rate' then o.value else ln(1 + greatest(o.value, 0)) end
    from generate_series(1, 120) g(i)
    left join lateral (select value from ripples.attention_obs o where o.series_id = p_series
                       and o.day >= (v_from + make_interval(months => g.i - 1))::date and o.day < (v_from + make_interval(months => g.i))::date
                       order by o.day desc limit 1) o on true;
  else
    v_from := p_day - 7 * 259; v_n := 260;
    insert into _zp(i, day, x)
    select g.i, v_from + 7 * (g.i - 1), case v_kind when 'level' then case when o.value > 0 then ln(o.value) end
                                                     when 'count' then ln(1 + greatest(o.value, 0)) when 'rate' then o.value else ln(1 + greatest(o.value, 0)) end
    from generate_series(1, 260) g(i)
    left join lateral (select value from ripples.attention_obs o where o.series_id = p_series
                       and o.day between v_from + 7 * (g.i - 1) and v_from + 7 * (g.i - 1) + 6 order by o.day desc limit 1) o on true;
  end if;
  select count(*) into v_nobs from _zp where x is not null;
  if v_nobs < 12 then return null; end if;
  with res as (
    select a.i, a.day, a.x - (select percentile_cont(0.5) within group (order by b.x) from _zp b where b.i between a.i - 6 and a.i + 6 and b.x is not null) r
    from _zp a where a.x is not null),
  moy as (select extract(month from day)::int k, percentile_cont(0.5) within group (order by r) eff, count(*) n from res group by 1)
  update _zp z set xt = z.x - coalesce((select eff from moy where moy.k = extract(month from z.day)::int and moy.n >= 3), 0) where z.x is not null;
  update _zp z set yhat = q.yhat from (
    select a.i,
           avg(b.xt) + ((sum((b.i - a.i) * b.xt) - count(*) * avg(b.i - a.i) * avg(b.xt)) / nullif(sum((b.i - a.i)^2) - count(*) * avg(b.i - a.i)^2, 0)) * (0 - avg(b.i - a.i)) yhat
    from _zp a join _zp b on b.i between a.i - v_w and a.i - 1 and b.xt is not null
    where a.xt is not null group by a.i having count(*) >= 6) q where q.i = z.i;
  update _zp z set sigma = greatest(coalesce((select 1.4826 * percentile_cont(0.5) within group (order by abs(b.xt - z.yhat)) from _zp b
                                              where b.i between z.i - v_w and z.i - 1 and b.xt is not null), 0),
                                    case v_kind when 'rate' then 0.01 when 'level' then 0.005 else 0.02 end)
  where z.yhat is not null;
  update _zp set z = (xt - yhat) / sigma where yhat is not null and sigma is not null;
  select array_agg(z::real order by i), array_agg((xt - yhat)::real order by i) into v_ar, v_res from _zp;
  select sigma into v_sigma from _zp where sigma is not null order by i desc limit 1;
  if v_sigma is null then return null; end if;
  v_kappa := case when v_nobs < 12 then 0 else least(1, v_nobs / 36.0) end;
  select percentile_cont(0.5) within group (order by x) into v_base from _zp where x is not null and i > v_n - 12;
  insert into ripples.att_zvec(series_id, from_day, grain, n, ar, resid, sigma, kappa, demean, value_kind, base_level, n_obs, n_obs_90, refreshed)
  values (p_series, v_from, s.grain, v_n, v_ar, v_res, v_sigma, v_kappa, 'none', v_kind, v_base, v_nobs, v_nobs, now())
  on conflict (series_id) do update set from_day = excluded.from_day, grain = excluded.grain, n = excluded.n, ar = excluded.ar, resid = excluded.resid,
    sigma = excluded.sigma, kappa = excluded.kappa, demean = 'none', value_kind = excluded.value_kind, base_level = excluded.base_level,
    n_obs = excluded.n_obs, n_obs_90 = excluded.n_obs_90, refreshed = now();
  return jsonb_build_object('nobs', v_nobs);
end $$;

-- Raw (undemeaned) z of a series: ar + c_t for panel-demeaned rows (c_t from att_zvec_ct), ar otherwise. Replaces the stored zraw.
create or replace function ripples.att_zvec_rawz(p_series bigint) returns real[]
language sql stable set search_path = '' as $$
  select case when z.demean = 'panel' then
           (select array_agg((u.z + coalesce(ct.c, 0))::real order by u.o)
              from unnest(z.ar) with ordinality u(z, o)
              left join ripples.att_zvec_ct ct on ct.source = s.source and ct.day = z.from_day + (u.o - 1)::int)
         else z.ar end
  from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id where z.series_id = p_series
$$;

-- Panel demeaning (ENGINE §3.5): c_t = median raw z over the source's panel series on day t (only with ≥ 50 panel series); ar = raw − c_t.
-- Idempotent without a stored zraw: rows already marked 'panel' are un-demeaned with the previous c_t before the new c_t is computed.
create or replace function ripples.att_zvec_demean(p_source text, p_day date) returns int
language plpgsql security definer set search_path = '' as $$
declare n_panel int; v_rows int := 0;
begin
  create temp table if not exists _zd (series_id bigint primary key, from_day date, raw real[], in_panel boolean) on commit drop;
  truncate _zd;
  insert into _zd
  select z.series_id, z.from_day, ripples.att_zvec_rawz(z.series_id), coalesce(t.in_panel, false)
  from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id left join ripples.att_topics t on t.topic_id = s.topic_id
  where s.source = p_source and z.grain = 'day';
  select count(*) into n_panel from _zd where in_panel;
  delete from ripples.att_zvec_ct where source = p_source;
  if n_panel < 50 then
    update ripples.att_zvec z set ar = d.raw, demean = 'none' from _zd d where d.series_id = z.series_id and z.demean = 'panel';
    return 0;
  end if;
  insert into ripples.att_zvec_ct(source, day, c, n_panel)
  select p_source, d.from_day + (u.o - 1)::int, percentile_cont(0.5) within group (order by u.z), count(*)
  from _zd d cross join lateral unnest(d.raw) with ordinality u(z, o)
  where d.in_panel and u.z is not null
  group by 2 having count(*) >= 50;
  update ripples.att_zvec z set ar = q.ar, demean = 'panel'
  from (select d.series_id, array_agg((u.z - coalesce(ct.c, 0))::real order by u.o) ar
        from _zd d cross join lateral unnest(d.raw) with ordinality u(z, o)
        left join ripples.att_zvec_ct ct on ct.source = p_source and ct.day = d.from_day + (u.o - 1)::int
        group by d.series_id) q
  where q.series_id = z.series_id;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

-- Synchronous driver (tests, small sources). Fits φ per source (≥ 200 year-ago pairs, clamped to [0, 1], shrunk n/(n+50) per series),
-- applies panel demeaning and writes common_shock days.
create or replace function ripples.att_build_zvec(p_day date default current_date - 1, p_sources text[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; src record; j jsonb; n_ser int := 0; n_src int := 0; v_phi float8; t0 timestamptz := clock_timestamp();
        sxy float8; sxx float8; nser int; npairs int; c_days int := 0;
begin
  for src in
    select s.source, s.grain, coalesce(m.channel, 'READ') channel
    from ripples.att_sources s left join ripples.att_engine_source_map m on m.source = s.source
    where s.enabled and coalesce(m.channel, '') <> 'MONEY'
      and (p_sources is null or s.source = any(p_sources))
      and exists (select 1 from ripples.att_series x where x.source = s.source and x.last_day >= p_day - 60)
    order by 1
  loop
    n_src := n_src + 1;
    if src.grain in ('day','hour') then
      perform ripples.att_zvec_weekday(src.source, p_day);
      sxy := 0; sxx := 0; nser := 0; npairs := 0;
      for r in select series_id from ripples.att_series where source = src.source and key <> '__total__' and last_day >= p_day - 60 loop
        j := ripples.att_zvec_series(r.series_id, p_day, 0);
        if j is not null then
          n_ser := n_ser + 1;
          if (j->>'nobs')::int >= 400 then sxy := sxy + (j->>'sxy')::float8; sxx := sxx + (j->>'sxx')::float8; nser := nser + 1; npairs := npairs + (j->>'n')::int; end if;
        end if;
      end loop;
      v_phi := case when sxx > 0 and npairs >= 200 then least(greatest(sxy / sxx, 0), 1) else 0 end;
      perform ripples.att_state_set('zvec.phi.' || src.source, jsonb_build_object('phi', v_phi, 'series', nser, 'pairs', npairs, 'day', p_day));
      if v_phi <> 0 then
        for r in select z.series_id, z.n_obs from ripples.att_zvec z join ripples.att_series s using (series_id)
                  where s.source = src.source and z.n_obs >= 400 and z.grain = 'day' and s.key <> '__total__' loop
          perform ripples.att_zvec_series(r.series_id, p_day, v_phi * r.n_obs / (r.n_obs + 50.0));
        end loop;
      end if;
      for r in select series_id from ripples.att_series where source = src.source and key = '__total__' and last_day >= p_day - 60 loop
        perform ripples.att_zvec_series(r.series_id, p_day, 0);
      end loop;
      perform ripples.att_zvec_demean(src.source, p_day);
    else
      for r in select series_id from ripples.att_series where source = src.source and last_day >= p_day - 120 loop
        j := ripples.att_zvec_series_periodic(r.series_id, p_day);
        if j is not null then n_ser := n_ser + 1; end if;
      end loop;
    end if;
  end loop;
  with c as (select day, source, c from ripples.att_zvec_ct where day between p_day - 2555 and p_day),
  f as (select day, array_agg(source order by source) sources, jsonb_object_agg(source, round(c::numeric, 3)) cs from c where abs(c) >= 1.5 group by day)
  insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
  select day, sources, cs, 'panel', p_day from f
  on conflict (day) do update set sources = excluded.sources, c_by_source = excluded.c_by_source, as_of = excluded.as_of;
  get diagnostics c_days = row_count;
  delete from ripples.att_common_days d where d.reason = 'panel' and d.as_of < p_day
     and not exists (select 1 from ripples.att_zvec_ct c where c.day = d.day and abs(c.c) >= 1.5);
  insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
  select d::date, '{}', '{}'::jsonb, 'registered', p_day
  from jsonb_array_elements_text(coalesce(ripples._att_cfg('common_days'), '[]'::jsonb)) d
  on conflict (day) do update set reason = 'registered';
  return jsonb_build_object('day', p_day, 'sources', n_src, 'series', n_ser, 'common_days', c_days,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- Chunked nightly build (cron att-zvec, every minute 05:50–07:20): each call works ≤ p_budget_s seconds; state in att_state 'zvec.run'.
-- ~1.5k series take ~25 minutes of DB time (0.5–2 s per series), inside the statement_timeout of pg_cron.
create or replace function ripples.att_build_zvec_step(p_day date default current_date - 1, p_budget_s int default 90) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb; t0 timestamptz := clock_timestamp(); j jsonb; n_done int := 0; v_phi float8;
        v_src text; v_stage text; sxy float8; sxx float8; nser int; npairs int; v_sid bigint;
begin
  st := coalesce(ripples.att_state_get('zvec.run'), '{}'::jsonb);
  if (st ->> 'day') is distinct from p_day::text then
    st := jsonb_build_object('day', p_day, 'started', now(), 'sources', (
            select coalesce(jsonb_agg(s.source order by (s.grain in ('day','hour')) desc, s.source), '[]'::jsonb)
            from ripples.att_sources s left join ripples.att_engine_source_map m on m.source = s.source
            where s.enabled and coalesce(m.channel, '') <> 'MONEY'
              and exists (select 1 from ripples.att_series x where x.source = s.source and x.last_day >= p_day - 60)),
          'done', '[]'::jsonb, 'cur', null, 'stage', null, 'pending', '[]'::jsonb, 'sxy', 0, 'sxx', 0, 'nser', 0, 'npairs', 0, 'series', 0);
    perform ripples.att_state_set('zvec.run', st);
  end if;
  if st ? 'finished' then return st - 'sources' - 'pending'; end if;

  while clock_timestamp() - t0 < make_interval(secs => p_budget_s) loop
    v_src := st ->> 'cur';
    if v_src is null then
      select x into v_src from jsonb_array_elements_text(st -> 'sources') x where not (st -> 'done') ? x limit 1;
      if v_src is null then
        with c as (select day, source, c from ripples.att_zvec_ct),
        f as (select day, array_agg(source order by source) sources, jsonb_object_agg(source, round(c::numeric, 3)) cs from c where abs(c) >= 1.5 group by day)
        insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
        select day, sources, cs, 'panel', p_day from f
        on conflict (day) do update set sources = excluded.sources, c_by_source = excluded.c_by_source, as_of = excluded.as_of;
        delete from ripples.att_common_days d where d.reason = 'panel' and d.as_of < p_day
           and not exists (select 1 from ripples.att_zvec_ct c where c.day = d.day and abs(c.c) >= 1.5);
        insert into ripples.att_common_days(day, sources, c_by_source, reason, as_of)
        select d::date, '{}', '{}'::jsonb, 'registered', p_day
        from jsonb_array_elements_text(coalesce(ripples._att_cfg('common_days'), '[]'::jsonb)) d
        on conflict (day) do update set reason = 'registered';
        st := st || jsonb_build_object('finished', now());
        perform ripples.att_state_set('zvec.run', st);
        return st - 'sources' - 'pending';
      end if;
      select s.grain into v_stage from ripples.att_sources s where s.source = v_src;
      if v_stage in ('day','hour') then
        perform ripples.att_zvec_weekday(v_src, p_day);
        st := st || jsonb_build_object('cur', v_src, 'stage', 'pass1', 'sxy', 0, 'sxx', 0, 'nser', 0, 'npairs', 0,
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and key <> '__total__' and last_day >= p_day - 60));
      else
        st := st || jsonb_build_object('cur', v_src, 'stage', 'periodic',
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and last_day >= p_day - 120));
      end if;
      perform ripples.att_state_set('zvec.run', st);
      continue;
    end if;
    v_stage := st ->> 'stage';
    if jsonb_array_length(st -> 'pending') = 0 then
      if v_stage = 'pass1' then
        sxy := (st ->> 'sxy')::float8; sxx := (st ->> 'sxx')::float8; nser := (st ->> 'nser')::int; npairs := coalesce((st ->> 'npairs')::int, 0);
        v_phi := case when sxx > 0 and npairs >= 200 then least(greatest(sxy / sxx, 0), 1) else 0 end;
        perform ripples.att_state_set('zvec.phi.' || v_src, jsonb_build_object('phi', v_phi, 'series', nser, 'pairs', npairs, 'day', p_day));
        st := st || jsonb_build_object('stage', 'pass2', 'phi', v_phi,
               'pending', case when v_phi <> 0 then (select coalesce(jsonb_agg(z.series_id order by z.series_id), '[]'::jsonb)
                                                     from ripples.att_zvec z join ripples.att_series s using (series_id)
                                                     where s.source = v_src and z.n_obs >= 400 and z.grain = 'day' and s.key <> '__total__') else '[]'::jsonb end);
      elsif v_stage = 'pass2' then
        st := st || jsonb_build_object('stage', 'totals',
               'pending', (select coalesce(jsonb_agg(series_id order by series_id), '[]'::jsonb) from ripples.att_series
                           where source = v_src and key = '__total__' and last_day >= p_day - 60));
      elsif v_stage = 'totals' then
        perform ripples.att_zvec_demean(v_src, p_day);
        st := st || jsonb_build_object('cur', null, 'stage', null, 'done', (st -> 'done') || to_jsonb(v_src));
      else
        st := st || jsonb_build_object('cur', null, 'stage', null, 'done', (st -> 'done') || to_jsonb(v_src));
      end if;
      perform ripples.att_state_set('zvec.run', st);
      continue;
    end if;
    v_sid := (st -> 'pending' ->> 0)::bigint;
    if v_stage = 'pass1' then
      j := ripples.att_zvec_series(v_sid, p_day, 0);
      if j is not null then
        st := st || jsonb_build_object('series', (st ->> 'series')::int + 1);
        if (j->>'nobs')::int >= 400 then
          st := st || jsonb_build_object('sxy', (st ->> 'sxy')::float8 + (j->>'sxy')::float8, 'sxx', (st ->> 'sxx')::float8 + (j->>'sxx')::float8,
                                         'nser', (st ->> 'nser')::int + 1, 'npairs', coalesce((st ->> 'npairs')::int, 0) + (j->>'n')::int);
        end if;
      end if;
    elsif v_stage = 'pass2' then
      select n_obs into nser from ripples.att_zvec where series_id = v_sid;
      perform ripples.att_zvec_series(v_sid, p_day, (st ->> 'phi')::float8 * nser / (nser + 50.0));
    elsif v_stage = 'totals' then
      perform ripples.att_zvec_series(v_sid, p_day, 0);
    else
      perform ripples.att_zvec_series_periodic(v_sid, p_day);
    end if;
    st := st || jsonb_build_object('pending', (st -> 'pending') - 0);
    n_done := n_done + 1;
    if n_done % 10 = 0 then perform ripples.att_state_set('zvec.run', st); end if;
  end loop;
  perform ripples.att_state_set('zvec.run', st);
  return jsonb_build_object('day', p_day, 'cur', st ->> 'cur', 'stage', st ->> 'stage', 'done', jsonb_array_length(st -> 'done'),
                            'of', jsonb_array_length(st -> 'sources'), 'series_this_call', n_done, 'pending', jsonb_array_length(st -> 'pending'));
end $$;

-- One stepper at a time (advisory lock); overlapping cron fires return immediately
create or replace function ripples.att_zvec_step_locked(p_day date default current_date - 1, p_budget_s int default 90) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not pg_try_advisory_lock(hashtext('ripples.att_build_zvec_step')) then
    return jsonb_build_object('skipped', 'another stepper holds the lock');
  end if;
  begin
    r := ripples.att_build_zvec_step(p_day, p_budget_s);
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_build_zvec_step'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_build_zvec_step'));
  return r;
end $$;

-- Convenience: AR value of a series on a day (null outside the array / missing)
create or replace function ripples.att_ar_at(p_series bigint, p_day date, p_agg boolean default false) returns real
language sql stable set search_path = '' as $$
  select case when p_agg and z.ar_agg is not null then z.ar_agg[(p_day - z.from_day) + 1] else z.ar[(p_day - z.from_day) + 1] end
  from ripples.att_zvec z where z.series_id = p_series and z.grain = 'day' and p_day between z.from_day and z.from_day + z.n - 1
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. security: service-only for every new object
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'ripples' and c.relkind = 'r' and c.relname like 'att\_%' loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on table ripples.%I from anon, authenticated, public', t);
  end loop;
  for t in select sequence_name from information_schema.sequences where sequence_schema = 'ripples' and sequence_name like 'att\_%' loop
    execute format('revoke all on sequence ripples.%I from anon, authenticated, public', t);
  end loop;
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
