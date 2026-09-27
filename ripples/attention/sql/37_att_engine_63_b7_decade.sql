-- Engine 6.3 batch b7: the decade backfill (2026-09-27).
--
-- Owner direction (2026-09-27): look at shocks from a decade and more ago and the population-level outcomes they
-- produced, then compare recent shocks against those historical patterns. The binding constraint found the same day:
-- the shock catalog started in 2019, so every exploration set held ~2.5 usable years of shocks even where outcome
-- panels reach back to 2005.
--
-- What this file does:
--  1. A separate event role 'library_hist' for U.S. hazard shocks beginning 2000-01-01 .. 2018-12-31, reconstructed from
--     OpenFEMA DisasterDeclarationsSummaries with exactly the grouping rules of att-library's femaEvents (named storms:
--     one event per storm and year; other declarations: one event per incident type + title and cluster of incident
--     begin dates <= 7 days apart). The separate role keeps every existing consumer of role 'library' (engines 6.1/6.2,
--     world rules, pond payloads) exactly as it was: only batches listed in engine63.hist_batches read these events,
--     and they enter neither the 6.1 prior set nor its replication set.
--  2. Historical shocks join the clean-control mask (att_fx63_fam_events), so a donor state hit by an older shock is
--     never used as a control. This is the stated 6.3.4 rule ("mask every known event"), now with more known events.
--  3. A second regime exclusion, the 2008-09 financial crisis (2008-09-01 .. 2009-06-30, NBER trough), handled exactly
--     like the pandemic regime: season-matched placebos from other years would read the collapse as an effect.
--  4. Collection is done database-side with pg_net (one OpenFEMA request at a time, every 2 minutes, honest UA, stop on
--     429/503), so the live att-library collector is untouched.
--
-- b7 pre-registration (written before any historical event exists in the database):
--   events    library_hist (2000-2018) + library (2019+) U.S. hazard families storm, hurricane, flood, wildfire, cold,
--             quake (heat excluded: no pre-2019 heat catalog). Split unchanged (2024-01-01): exploration gains the older
--             shocks, confirmation stays on held-out 2024+ shocks.
--   outcomes  monthly state panels fred.state nonfarm_m, cons_m, leih_m, bppriv_m, srvo_m, eduh_m, fire_m, govt_m,
--             pbsv_m, trad_m, mfg_m (first releases; usable from each panel's first vintage, 2005-06 for most);
--             weekly dol.claims ic_w / cw_w (panel extended to 2010-01) and cdc.deaths all_w (2014+)
--   windows   monthly: immediate (pre 18, post 3, lag 1), delayed (pre 18, post 6, lag 6) and NEW year-after
--             (pre 18, post 12, lag 12 = months 13-24); weekly: b1 windows for claims, b6 windows for deaths
--   rule      unchanged 6.3.4 + the seasonal robustness check on held-out events, else withheld
--   exposure  b4 (and b6, when it runs) explored 2019-2023 shocks for some of these outcome pairs; declared as prior
--             exposure. Phase 2 (annual population outcomes 1-5 years out: migration, business counts, births;
--             and recent-shock analog matching) is a later batch, not part of b7.

-- 1. role -------------------------------------------------------------------------------------------------------------
alter table ripples.att_events drop constraint att_events_role_check;
alter table ripples.att_events add constraint att_events_role_check
  check (role = any (array['real', 'decoy', 'library', 'positive_control', 'library_hist']));

do $$ declare d text;
  a1 text := $a$v_onset < date '2019-01-01'$a$;
  -- no CASE here: a PL/pgSQL IF condition ends at the first THEN
  b1 text := $b$(v_role <> 'library_hist' and v_onset < date '2019-01-01') or (v_role = 'library_hist' and (v_onset < date '2000-01-01' or v_onset >= date '2019-01-01'))$b$;
  a2 text := $a$v_role not in ('library', 'positive_control')$a$;
  b2 text := $b$v_role not in ('library', 'positive_control', 'library_hist')$b$;
  a3 text := $a$v_note := case when v_role <> 'library' then 'positive control: in neither set (ENGINE §5.7)'$a$;
  b3 text := $b$v_note := case when v_role = 'library_hist' then 'historical shock (2000-2018): engine 6.3 hist batches only, in neither set' when v_role <> 'library' then 'positive control: in neither set (ENGINE §5.7)'$b$;
begin
  d := pg_get_functiondef('ripples.att_library_upsert(jsonb)'::regprocedure);
  if position('library_hist' in d) > 0 then return; end if;
  if position(a1 in d) = 0 or position(a2 in d) = 0 or position(a3 in d) = 0 then raise exception 'att_library_upsert anchors'; end if;
  execute replace(replace(replace(d, a1, b1), a2, b2), a3, b3);
end $$;

-- 2. mask + freeze read historical shocks (freeze: only for engine63.hist_batches) ---------------------------------------
do $$ declare d text; a text := $a$e.role = 'library'$a$; b text := $b$e.role in ('library', 'library_hist')$b$;
begin
  d := pg_get_functiondef('ripples.att_fx63_fam_events_build()'::regprocedure);
  if position('library_hist' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'fam_events_build anchor'; end if;
  execute replace(d, a, b);
end $$;

do $$ declare d text; a text := $a$ev.role = 'library'$a$;
  b text := $b$(ev.role = 'library' or (ev.role = 'library_hist' and p_batch in (select jsonb_array_elements_text(coalesce(cfg -> 'hist_batches', '[]'::jsonb)))))$b$;
begin
  d := pg_get_functiondef('ripples.att_fx63_freeze(text,text)'::regprocedure);
  if position('library_hist' in d) > 0 then return; end if;
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 2 then raise exception 'freeze anchors'; end if;
  execute replace(d, a, b);
end $$;

-- 3. config: hist batch, recession regime, claims panel start ---------------------------------------------------------
update ripples.att_config set value = value
  || jsonb_build_object('hist_batches', '["fx63-b7-decade"]'::jsonb)
  || jsonb_build_object('regime_exclusions', coalesce(value -> 'regime_exclusions', '[]'::jsonb) || '[{"from":"2008-09-01","to":"2009-06-30","panels":"all","reason":"financial-crisis regime (2008-09 to the NBER trough): state series collapsed together; season-matched placebos from other years would read it as an effect"}]'::jsonb)
  || jsonb_build_object('panel_from', coalesce(value -> 'panel_from', '{}'::jsonb) || '{"dol.claims:ic":"2010-01-01","dol.claims:cw":"2010-01-01"}'::jsonb)
 where key = 'engine63' and not (value -> 'regime_exclusions')::text like '%financial-crisis%';

-- 4. grid set b7 ------------------------------------------------------------------------------------------------------
do $$ declare def text;
  a text := $a$('b6', 'cdc.deaths', 'all_w', 'state', 'health', '[[12,4,1,"immediate"],[12,8,5,"delayed"]]')) p(pset$a$;
  b text := $b$('b6', 'cdc.deaths', 'all_w', 'state', 'health', '[[12,4,1,"immediate"],[12,8,5,"delayed"]]'),
      ('b7', 'fred.state', 'nonfarm_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'cons_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'leih_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'bppriv_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'srvo_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'eduh_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'fire_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'govt_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'pbsv_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'trad_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'fred.state', 'mfg_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"],[18,12,12,"yearafter"]]'),
      ('b7', 'dol.claims', 'ic', 'state', 'labor', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'),
      ('b7', 'dol.claims', 'cw', 'state', 'labor', '[[8,4,1,"immediate"],[8,4,5,"delayed"]]'),
      ('b7', 'cdc.deaths', 'all_w', 'state', 'health', '[[12,4,1,"immediate"],[12,8,5,"delayed"]]')) p(pset$b$;
  a2 text := $a$(p_set <> 'b2' or f.family <> 'hazard.quake')$a$;
  b2 text := $b$(p_set <> 'b2' or f.family <> 'hazard.quake') and (p_set <> 'b7' or f.family <> 'hazard.heat')$b$;
begin
  def := pg_get_functiondef('ripples.att_fx63_grid_spec(text)'::regprocedure);
  if position('''b7''' in def) > 0 then return; end if;
  if position(a in def) = 0 or position(a2 in def) = 0 then raise exception 'grid_spec anchors'; end if;
  execute replace(replace(def, a, b), a2, b2);
end $$;

-- 5. database-side OpenFEMA collection (declaration years 2000..2019; events kept if incident began 2000..2018) -------
create table if not exists ripples.att_hist_fema_req (
  year int not null, skip int not null default 0, req_id bigint, status text not null default 'queued', n int,
  requested_at timestamptz, done_at timestamptz, primary key (year, skip));
create table if not exists ripples.att_hist_fema (
  num int not null, state text not null, day date not null, type text, it text, title text, began date,
  primary key (num, state, day, began, title));
alter table ripples.att_hist_fema_req enable row level security;
alter table ripples.att_hist_fema enable row level security;
revoke all on ripples.att_hist_fema_req, ripples.att_hist_fema from anon, authenticated, public;
insert into ripples.att_hist_fema_req(year) select y from generate_series(2000, 2019) y on conflict do nothing;

create or replace function ripples.att_hist_fema_tick() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q record; r record; page jsonb; v_n int; v_out jsonb := '{}'::jsonb; url text;
begin
  -- collect a finished request
  for q in select * from ripples.att_hist_fema_req where status = 'requested' order by year, skip loop
    select * into r from net._http_response h where h.id = q.req_id;
    if r.id is null then
      if q.requested_at < now() - interval '10 minutes' then update ripples.att_hist_fema_req set status = 'queued', req_id = null where year = q.year and skip = q.skip; end if;
      continue;
    end if;
    if r.status_code in (429, 503) then
      update ripples.att_hist_fema_req set status = 'stopped', done_at = now() where year = q.year and skip = q.skip;   -- stop, do not retry
      return jsonb_build_object('stop', r.status_code, 'year', q.year);
    end if;
    if r.status_code <> 200 then update ripples.att_hist_fema_req set status = 'error:' || coalesce(r.status_code::text, left(r.error_msg, 60)), done_at = now() where year = q.year and skip = q.skip; continue; end if;
    page := r.content::jsonb -> 'DisasterDeclarationsSummaries';
    insert into ripples.att_hist_fema(num, state, day, type, it, title, began)
      select (x ->> 'disasterNumber')::int, upper(coalesce(x ->> 'state', '')), left(x ->> 'declarationDate', 10)::date, upper(coalesce(x ->> 'declarationType', '')),
             coalesce(x ->> 'incidentType', 'Other'), coalesce(x ->> 'declarationTitle', ''), left(coalesce(x ->> 'incidentBeginDate', x ->> 'declarationDate'), 10)::date
        from jsonb_array_elements(coalesce(page, '[]'::jsonb)) x
       where x ->> 'disasterNumber' ~ '^\d+$' and x ->> 'declarationDate' ~ '^\d{4}-\d{2}-\d{2}'
      on conflict do nothing;
    v_n := jsonb_array_length(coalesce(page, '[]'::jsonb));
    update ripples.att_hist_fema_req set status = 'done', n = v_n, done_at = now() where year = q.year and skip = q.skip;
    if v_n >= 10000 then insert into ripples.att_hist_fema_req(year, skip) values (q.year, q.skip + 10000) on conflict do nothing; end if;
    v_out := v_out || jsonb_build_object('collected', q.year || '/' || q.skip, 'n', v_n);
  end loop;
  -- one request in flight at a time
  if exists (select 1 from ripples.att_hist_fema_req where status = 'requested') or exists (select 1 from ripples.att_hist_fema_req where status = 'stopped') then return v_out; end if;
  select * into q from ripples.att_hist_fema_req where status = 'queued' order by year, skip limit 1;
  if q.year is null then return v_out || jsonb_build_object('complete', true); end if;
  url := 'https://www.fema.gov/api/open/v2/DisasterDeclarationsSummaries?%24select=disasterNumber,declarationDate,declarationType,incidentType,declarationTitle,state,incidentBeginDate'
      || '&%24filter=' || replace(format('declarationDate ge ''%s-01-01T00:00:00.000Z'' and declarationDate le ''%s-12-31T23:59:59.999Z''', q.year, q.year), ' ', '%20')
      || '&%24orderby=declarationDate&%24top=10000&%24skip=' || q.skip;
  update ripples.att_hist_fema_req set status = 'requested', requested_at = now(),
    req_id = net.http_get(url, '{}'::jsonb, '{"user-agent":"ripples-research/0.2 (+https://bensunter.com/ripples/methods/)","accept":"application/json"}'::jsonb, 90000)
   where year = q.year and skip = q.skip;
  return v_out || jsonb_build_object('requested', q.year || '/' || q.skip);
end $$;

-- femaEvents in SQL (same family map, storm naming, 7-day clustering, magnitude, slugs and labels as att-library)
create or replace function ripples.att_hist_fema_build() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; res jsonb := '[]'::jsonb; i int := 0; v_n int;
begin
  with fam(it, family) as (values
      ('hurricane', 'hazard.storm'), ('tropical storm', 'hazard.storm'), ('typhoon', 'hazard.storm'), ('tropical depression', 'hazard.storm'),
      ('coastal storm', 'hazard.storm'), ('severe storm', 'hazard.storm'), ('severe storm(s)', 'hazard.storm'), ('tornado', 'hazard.storm'),
      ('straight-line winds', 'hazard.storm'), ('flood', 'hazard.flood'), ('dam/levee break', 'hazard.flood'), ('mud/landslide', 'hazard.flood'),
      ('fire', 'hazard.wildfire'), ('winter storm', 'hazard.cold'), ('severe ice storm', 'hazard.cold'), ('snowstorm', 'hazard.cold'),
      ('freezing', 'hazard.cold'), ('earthquake', 'hazard.quake')),
  recs as (
    select h.*, f.family, ripples.att_storm_name(h.title) storm from ripples.att_hist_fema h join fam f on f.it = lower(h.it)
     where h.began >= date '2000-01-01' and h.began < date '2019-01-01'),
  keyed as (
    select r.*, case when storm is not null then 'storm|' || storm || '|' || extract(year from began)::int else it || '|' || upper(btrim(title)) end k from recs r),
  brk as (
    select k2.*, case when storm is null and began > max(began) over (partition by k order by began, num rows between unbounded preceding and 1 preceding) + 7 then 1 else 0 end nb from keyed k2),
  grp as (select b.*, sum(nb) over (partition by k order by began, num rows unbounded preceding) gi from brk b),
  g as (
    select k, gi, min(storm) storm, min(family) family, min(it) it, min(title) title, min(began) began, count(*) areas,
           array_agg(distinct state order by state) filter (where state ~ '^[A-Z]{2}$') states,
           array_agg(distinct type order by type) types, (array_agg(distinct num order by num))[1:8] nums, array_agg(title) titles
      from grp group by k, gi),
  lbl as (
    select g.*, case when exists (select 1 from unnest(titles) t where t ~* 'HURRICANE') then 'Hurricane'
                     when exists (select 1 from unnest(titles) t where t ~* 'TYPHOON') then 'Typhoon' else 'Tropical storm' end kind,
           trim(both '-' from left(trim(both '-' from regexp_replace(lower(coalesce(nullif(title, ''), it)), '[^a-z0-9]+', '-', 'g')), 60)) sl
      from g)
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'role', 'library_hist', 'onset', began, 'states', to_jsonb(coalesce(states, '{}')), 'merge', true,
           'magnitude', round(ln(1 + areas)::numeric, 3), 'source', 'OpenFEMA DisasterDeclarationsSummaries',
           'ref', array_to_string(types, '/') || '-' || array_to_string(nums, ','), 'defined_by', '["fema.decl"]'::jsonb,
           'slug', case when storm is not null then 'storm-' || storm || '-' || extract(year from began)::int else 'fema-' || sl || '-' || began end,
           'storm', storm, 'family', case when storm is not null then 'hazard.storm' else family end,
           'label', case when storm is not null then kind || ' ' || initcap(storm) || ' (' || extract(year from began)::int || ')'
                         else left(initcap(coalesce(nullif(title, ''), it)) || ' (' || it || ', ' || began || ')', 200) end,
           'label_weak', case when storm is not null then kind = 'Tropical storm' end)))
    into v_rows from lbl;
  v_n := coalesce(jsonb_array_length(v_rows), 0);
  while i < v_n loop
    res := res || jsonb_build_array(ripples.att_library_upsert((select jsonb_agg(x) from (select x from jsonb_array_elements(v_rows) with ordinality e(x, o) where o > i and o <= i + 200) z)));
    i := i + 200;
  end loop;
  perform ripples.att_fx63_fam_events_build();
  return jsonb_build_object('events', v_n, 'upserts', res);
end $$;
revoke all on function ripples.att_hist_fema_tick(), ripples.att_hist_fema_build() from anon, authenticated, public;

select cron.schedule('att-hist-fema', '*/2 * * * *', $c$
  select ripples.att_hist_fema_tick() where exists (select 1 from ripples.att_hist_fema_req where status in ('queued', 'requested'))
$c$);

-- 6. pre-registration -------------------------------------------------------------------------------------------------
select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'fx63_batch', 'batch', 'fx63-b7-decade', 'stage', 'pre-registration', 'method', '6.3.4 + hist events',
  'grid_spec_sha256', encode(extensions.digest(ripples._canon(ripples.att_fx63_grid_spec('b7'))::text, 'sha256'), 'hex'),
  'note', 'seventh blind batch ("decade backfill"), declared before any historical shock exists in the database: U.S. hazard shocks with incident '
       || 'begin 2000-01-01..2018-12-31 reconstructed from OpenFEMA DisasterDeclarationsSummaries (declaration years 2000-2019) with att-library''s femaEvents '
       || 'grouping, stored as role library_hist (read only by engine63.hist_batches = [fx63-b7-decade]; added to the clean-control mask); new regime exclusion '
       || '2008-09-01..2009-06-30 (financial crisis) alongside the pandemic regime; claims panels extended to 2010-01; families storm, hurricane, flood, wildfire, '
       || 'cold, quake (heat excluded: no pre-2019 catalog); outcomes nonfarm/cons/leih/bppriv/srvo/eduh/fire/govt/pbsv/trad/mfg (monthly: immediate, delayed, '
       || 'year-after = months 13-24) + dol.claims ic/cw (weekly b1 windows) + cdc.deaths all (weekly b6 windows); split 2024-01-01 unchanged; same selection '
       || 'rule, decoys, MDE gate, clean-control mask; seasonal robustness check on held-out events or withheld. Prior exposure: b4 explored 2019-2023 shocks '
       || 'for nonfarm/cons/leih/bppriv. Phase 2 (annual population outcomes 1-5 years out; recent-shock analog matching) is a separate later batch.'),
  ripples.att_fx63_grid_spec('b7'));
