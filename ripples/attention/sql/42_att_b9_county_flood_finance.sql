-- 42: batch b9 — county-level test of the one lead from b6/b7 (2026-09-27).
--
-- The lead: FEMA-declared floods are followed by fewer finance / insurance / real-estate jobs a year later. At state
-- level it was b6's nearest miss (months 6-11, q 0.32) and b7's best result (months 13-24, -3.3%, q 0.030, 10/11
-- held-out floods negative) but failed the power gate (11 held-out events). State totals dilute a county-level shock,
-- and b8 showed that confirmation nulls must be year-matched. b9 answers both.
--
-- PRE-REGISTRATION (written, and this file's test function hashed into the ledger, before any county employment row
-- exists in the database):
--   shocks     FEMA major-disaster declarations (type DR) with incident type Flood, Dam/Levee Break or Mud/Landslide
--              (the engine's hazard.flood family), one event per disaster number; treated units = the designated
--              counties (statewide designations excluded); onset = month of the earliest incident begin date.
--              Eligible onsets 2001-03 .. 2024-03 (12 pre months and 24 post months inside the data); events whose
--              [-12, +24] month span touches a regime exclusion (2008-09-01..2009-06-30, 2020-02-15..2021-06-30) dropped.
--   outcome    BLS QCEW private-sector employment in Financial Activities (supersector 1023, ownership 5, county
--              level 73), monthly, log. Change per county = mean log employment over the window minus mean over the
--              12 pre months (a county's own seasonality and level cancel).
--   comparison donors = counties in the SAME STATE with no FEMA declaration of any kind (non-statewide) whose incident
--              began within [-12, +24] months of the onset. Same state and same calendar months, so state-wide and
--              year-wide swings cancel (the b8 lesson). Event effect d = mean(treated) - mean(donors); needs >= 1
--              treated county with full data and >= 5 donors.
--   null       in-space permutation: per event, the same number of pseudo-treated counties drawn from the donors
--              (same state, same dates, so exactly year- and season-matched), 1,000 draws, seed fixed.
--   statistic  S = mean of d over events; one-sided p = (1 + #{S_k <= S}) / 1001.
--   PRIMARY    H1: months 13-24, financial activities. Supported if S < 0 and p <= 0.05. One test, no multiplicity.
--   SECONDARY  (reported, never headline): months 6-11 finance; months 13-24 total private employment (industry 10,
--              level 71) as a specificity check; months 13-24 finance minus total (is finance hit harder than the
--              county economy as a whole?). Also: share of events with d < 0, leave-one-state-out range.
--   disclosed  every eligible event was already seen at STATE level by b6/b7 exploration; the county measurement and
--              the within-state donors are new, so this is a partly independent check, not a fresh sample.
-- Collection is database-side with pg_net: honest UA, one request a minute, stop on 403/429/503, each response parsed
-- (< 10k rows per transaction) and deleted from net._http_response straight away.

create table if not exists ripples.att_b9_qcew (
  area text not null, ind text not null, ym date not null, emp int not null, primary key (ind, area, ym));
create table if not exists ripples.att_b9_decl (
  num int not null, county text not null, type text, it text, began date, declared date, primary key (num, county));
create table if not exists ripples.att_b9_req (
  src text not null, k text not null, status text not null default 'queued', req_id bigint, n int,
  requested_at timestamptz, done_at timestamptz, primary key (src, k));
alter table ripples.att_b9_qcew enable row level security;
alter table ripples.att_b9_decl enable row level security;
alter table ripples.att_b9_req enable row level security;
revoke all on ripples.att_b9_qcew, ripples.att_b9_decl, ripples.att_b9_req from anon, authenticated, public;

-- queue: QCEW 2000Q1..2026Q1 for supersector 1023 and total 10; FEMA declarations since 2000, 10k per page
insert into ripples.att_b9_req(src, k)
  select 'qcew', y || '/' || q || '/' || ind from generate_series(2000, 2026) y, generate_series(1, 4) q, unnest(array['1023', '10']) ind
   where (y, q) <= (2026, 1)
on conflict do nothing;
insert into ripples.att_b9_req(src, k) values ('fema', '0') on conflict do nothing;

create or replace function ripples.att_b9_tick() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q record; r record; v_n int; v_url text; v_y int; v_q int; v_ind text; v_page jsonb;
  ua jsonb := '{"user-agent":"ripples-research/0.2 (+https://bensunter.com/ripples/methods/)","accept":"*/*"}';
begin
  for q in select * from ripples.att_b9_req where status = 'requested' loop
    select * into r from net._http_response h where h.id = q.req_id;
    if r.id is null then
      if q.requested_at < now() - interval '10 minutes' then update ripples.att_b9_req set status = 'queued', req_id = null where src = q.src and k = q.k; end if;
      continue;
    end if;
    if r.status_code in (403, 429, 503) then
      update ripples.att_b9_req set status = 'stopped', done_at = now() where src = q.src and k = q.k;   -- stop, no retry today
      return jsonb_build_object('stop', r.status_code, 'k', q.k);
    end if;
    if r.status_code is distinct from 200 then
      update ripples.att_b9_req set status = 'error:' || coalesce(r.status_code::text, left(r.error_msg, 40)), done_at = now() where src = q.src and k = q.k;
      delete from net._http_response where id = q.req_id;
      continue;
    end if;
    if q.src = 'qcew' then
      v_ind := split_part(q.k, '/', 3);
      insert into ripples.att_b9_qcew(area, ind, ym, emp)
        select x.f[1], v_ind, make_date(x.f[6]::int, (x.f[7]::int - 1) * 3 + mm, 1), x.f[9 + mm]::int
          from (select string_to_array(replace(l, '"', ''), ',') f from regexp_split_to_table(r.content, E'\n') l) x
          cross join generate_series(1, 3) mm
         where x.f[2] = '5' and x.f[4] = case v_ind when '1023' then '73' else '71' end
           and x.f[1] ~ '^[0-9]{5}$' and x.f[1] !~ '000$' and coalesce(x.f[8], '') <> 'N'
           and x.f[6] ~ '^[0-9]{4}$' and x.f[7] ~ '^[1-4]$' and x.f[9 + mm] ~ '^[0-9]+$'
      on conflict do nothing;
      get diagnostics v_n = row_count;
    else
      v_page := r.content::jsonb -> 'DisasterDeclarationsSummaries';
      insert into ripples.att_b9_decl(num, county, type, it, began, declared)
        select (x ->> 'disasterNumber')::int, (x ->> 'fipsStateCode') || (x ->> 'fipsCountyCode'), x ->> 'declarationType', x ->> 'incidentType',
               left(coalesce(x ->> 'incidentBeginDate', x ->> 'declarationDate'), 10)::date, left(x ->> 'declarationDate', 10)::date
          from jsonb_array_elements(coalesce(v_page, '[]'::jsonb)) x
         where x ->> 'fipsStateCode' ~ '^[0-9]{2}$' and x ->> 'fipsCountyCode' ~ '^[0-9]{3}$' and x ->> 'disasterNumber' ~ '^[0-9]+$'
      on conflict do nothing;
      v_n := jsonb_array_length(coalesce(v_page, '[]'::jsonb));
      if v_n >= 10000 then insert into ripples.att_b9_req(src, k) values ('fema', (q.k::int + 10000)::text) on conflict do nothing; end if;
    end if;
    update ripples.att_b9_req set status = 'done', n = v_n, done_at = now() where src = q.src and k = q.k;
    delete from net._http_response where id = q.req_id;
  end loop;
  if exists (select 1 from ripples.att_b9_req where status in ('requested', 'stopped')) then return jsonb_build_object('waiting', true); end if;
  select * into q from ripples.att_b9_req where status = 'queued' order by src, k limit 1;   -- 'fema' sorts before 'qcew'
  if q.src is null then return jsonb_build_object('complete', true); end if;
  if q.src = 'qcew' then
    v_y := split_part(q.k, '/', 1)::int; v_q := split_part(q.k, '/', 2)::int; v_ind := split_part(q.k, '/', 3);
    v_url := format('https://data.bls.gov/cew/data/api/%s/%s/industry/%s.csv', v_y, v_q, v_ind);
  else
    v_url := 'https://www.fema.gov/api/open/v2/DisasterDeclarationsSummaries?%24select=disasterNumber,declarationType,incidentType,fipsStateCode,fipsCountyCode,incidentBeginDate,declarationDate'
          || '&%24filter=declarationDate%20ge%20%272000-01-01T00:00:00.000Z%27&%24orderby=id&%24top=10000&%24skip=' || q.k;
  end if;
  update ripples.att_b9_req set status = 'requested', requested_at = now(), req_id = net.http_get(v_url, '{}'::jsonb, ua, 120000)
   where src = q.src and k = q.k;
  return jsonb_build_object('requested', q.src || ' ' || q.k);
end $$;

-- the test (frozen: its definition hash is in the pre-registration entry)
create or replace function ripples.att_b9_test(p_ind text, p_lo int, p_hi int, p_k int default 1000) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare reg jsonb := coalesce(ripples._att_cfg('engine63') -> 'regime_exclusions', '[]'::jsonb); v_s float8; v_p float8; v_out jsonb;
begin
  perform setseed(0.4242);
  drop table if exists pg_temp._b9ev; drop table if exists pg_temp._b9y; drop table if exists pg_temp._b9d;
  create temp table _b9ev on commit drop as
    select e.num, e.sf, e.m0, e.cty from (
      select d.num, left(min(d.county), 2) sf, date_trunc('month', min(d.began))::date m0, array_agg(distinct d.county) cty
        from ripples.att_b9_decl d
       where d.type = 'DR' and d.it in ('Flood', 'Dam/Levee Break', 'Mud/Landslide') and d.county !~ '000$'
       group by d.num having count(distinct left(d.county, 2)) = 1) e
     where e.m0 >= date '2001-03-01' and e.m0 < date '2024-04-01'
       and not exists (select 1 from jsonb_array_elements(reg) r
                        where (e.m0 - interval '12 months')::date <= (r ->> 'to')::date and (e.m0 + interval '24 months')::date >= (r ->> 'from')::date);
  -- per event x county: window mean minus pre mean of log employment (full months only); 'diff' = finance minus total
  create temp table _b9y on commit drop as
    with base as (
      select e.num, q.area, q.ind,
             avg(ln(q.emp)) filter (where q.ym between (e.m0 + make_interval(months => p_lo))::date and (e.m0 + make_interval(months => p_hi))::date) w,
             count(*) filter (where q.ym between (e.m0 + make_interval(months => p_lo))::date and (e.m0 + make_interval(months => p_hi))::date) nw,
             avg(ln(q.emp)) filter (where q.ym between (e.m0 - interval '12 months')::date and (e.m0 - interval '1 month')::date) pr,
             count(*) filter (where q.ym between (e.m0 - interval '12 months')::date and (e.m0 - interval '1 month')::date) np
        from _b9ev e join ripples.att_b9_qcew q on left(q.area, 2) = e.sf and q.emp > 0
         and q.ind = any(case when p_ind = 'diff' then array['1023', '10'] else array[p_ind] end)
         and q.ym between (e.m0 - interval '12 months')::date and (e.m0 + make_interval(months => p_hi))::date
       group by e.num, q.area, q.ind),
    ok as (select num, area, ind, w - pr y from base where nw = p_hi - p_lo + 1 and np = 12),
    yy as (select num, area, case when p_ind = 'diff' then max(y) filter (where ind = '1023') - max(y) filter (where ind = '10') else max(y) end y
             from ok group by num, area having p_ind <> 'diff' or count(*) = 2)
    select yy.num, yy.area, yy.y,
           case when yy.area = any(e.cty) then 'T'
                when exists (select 1 from ripples.att_b9_decl d2 where d2.county = yy.area
                              and d2.began between (e.m0 - interval '12 months')::date and (e.m0 + interval '24 months')::date) then 'X'
                else 'D' end grp
      from yy join _b9ev e on e.num = yy.num;
  delete from _b9y where grp = 'X';
  delete from _b9y y where y.num in (select num from _b9y group by num having count(*) filter (where grp = 'T') < 1 or count(*) filter (where grp = 'D') < 5);
  -- observed effects and the permutation null (pseudo-treated drawn from donors, same count as treated)
  create temp table _b9d on commit drop as
    with nt as (select num, count(*) filter (where grp = 'T') n_t from _b9y group by num),
    obs as (select num, avg(y) filter (where grp = 'T') - avg(y) filter (where grp = 'D') d from _b9y group by num),
    dr as (select k.k, y.num, y.y, row_number() over (partition by k.k, y.num order by random()) rk
             from _b9y y cross join generate_series(1, p_k) k(k) where y.grp = 'D'),
    perm as (select dr.k, dr.num, avg(dr.y) filter (where dr.rk <= nt.n_t) - avg(dr.y) filter (where dr.rk > nt.n_t) d
               from dr join nt on nt.num = dr.num group by dr.k, dr.num)
    select 0 k, obs.num, obs.d from obs union all select perm.k, perm.num, perm.d from perm;
  select avg(d) into v_s from _b9d where k = 0;
  select (1 + count(*) filter (where s <= v_s))::float8 / (1 + count(*)) into v_p from (select k, avg(d) s from _b9d where k > 0 group by k) z;
  select jsonb_build_object('ind', p_ind, 'window', jsonb_build_array(p_lo, p_hi), 'n_events', count(*),
           'n_treated', (select count(*) from _b9y where grp = 'T'), 'n_donor_rows', (select count(*) from _b9y where grp = 'D'),
           'effect_mean_log', round(v_s::numeric, 5), 'effect_pct', round(((exp(v_s) - 1) * 100)::numeric, 2), 'p_one_sided', round(v_p::numeric, 4),
           'share_events_negative', round(avg(case when d < 0 then 1 else 0 end)::numeric, 3), 'k', p_k,
           'loso_range', (select jsonb_build_array(round(min(s)::numeric, 5), round(max(s)::numeric, 5))
                            from (select e.sf, (select avg(d0.d) from _b9d d0 join _b9ev e2 on e2.num = d0.num where d0.k = 0 and e2.sf <> e.sf) s
                                    from (select distinct sf from _b9ev) e) z))
    into v_out from _b9d where k = 0;
  return v_out;
end $$;
revoke all on function ripples.att_b9_tick(), ripples.att_b9_test(text, int, int, int) from anon, authenticated, public;

select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'b9_run', 'run', 'b9-county-flood-finance', 'stage', 'pre-registration', 'file', '42_att_b9_county_flood_finance.sql',
  'test_function_md5', md5(pg_get_functiondef('ripples.att_b9_test(text,integer,integer,integer)'::regprocedure)),
  'note', 'Written before any county employment row exists. Shocks: FEMA DR declarations, incident Flood / Dam-Levee Break / Mud-Landslide, '
       || 'designated counties, onset 2001-03..2024-03, regime spans dropped. Outcome: QCEW private Financial Activities (1023) county monthly log '
       || 'employment, window mean minus 12-month pre mean. Donors: same-state counties with no declaration of any kind in [-12, +24] months. '
       || 'Null: in-space permutation, 1,000 draws (year- and season-matched by construction). PRIMARY (single test): months 13-24 finance, '
       || 'supported if mean effect < 0 and one-sided p <= 0.05. SECONDARY: months 6-11 finance; months 13-24 total private (10); finance minus '
       || 'total. Disclosed: all eligible events were seen at state level by b6/b7.'),
  jsonb_build_object('primary', jsonb_build_object('ind', '1023', 'lo', 13, 'hi', 24, 'alpha', 0.05, 'direction', 'negative'),
                     'secondary', jsonb_build_array(jsonb_build_array('1023', 6, 11), jsonb_build_array('10', 13, 24), jsonb_build_array('diff', 13, 24))));

select cron.schedule('att-b9-collect', '* * * * *', $c$
  set statement_timeout = '100s';
  select ripples.att_b9_tick() where exists (select 1 from ripples.att_b9_req where status in ('queued', 'requested'))
$c$);

-- 16:15 UTC (not part of b9): owner-provided keys stored in Vault (census_api_key updated; api_data_gov_key, epa_aqs_key,
-- epa_aqs_email added). att_secret's allow-list now includes the three new names. epa_aqs_email is sent only to
-- aqs.epa.gov together with epa_aqs_key (EPA requires both on every request).
create or replace function public.att_secret(p_name text) returns text language sql stable security definer set search_path to '' as $function$
  select decrypted_secret from vault.decrypted_secrets where name = p_name and name in ('fred_api_key','sec_contact_email','bls_api_key','eia_api_key','census_api_key','noaa_cdo_token','youtube_api_key','twelvedata_api_key','alphavantage_api_key','stackexchange_key','github_token','api_data_gov_key','epa_aqs_key','epa_aqs_email') limit 1; $function$;
