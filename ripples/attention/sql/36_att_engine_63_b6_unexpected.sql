-- Engine 6.3 batch b6: "unexpected places" (2026-09-27).
--
-- Owner direction (2026-09-27): storm -> power, inflation report -> inflation expectations is what everyone already
-- knows. Florida is built to absorb hurricanes, so the first ripple may simply die out there. The product is the link
-- nobody would guess: look well beyond power and gas for behaviours and outcomes that trace back to the same shock.
--
-- Diagnosis at the time of writing: every outcome the engine had ever tested was first-order (grid demand, disaster
-- declarations, jobless claims, business applications, construction / leisure jobs, permits, listings), so every
-- confirmation was expected by mechanism. b6 widens the outcome menu to where an unexpected ripple could land.
--
-- Pre-registered here, before any b6 panel is built or any b6 test is run:
--   outcomes  fred.state srvo_m (other services: repair & maintenance, personal care, laundry), eduh_m (private
--             education & health), fire_m (financial activities, incl. insurance), govt_m (government), pbsv_m
--             (professional & business services, incl. temp help and remediation), trad_m (trade, transportation &
--             utilities), mfg_m (manufacturing) -- BLS CES state supersectors via FRED/ALFRED, first releases, monthly;
--             cdc.deaths all_w -- CDC/NCHS weekly all-cause deaths by state (2014-2019 final, 2020+ provisional; the
--             last 8 weeks before each file's data_as_of are never ingested)
--   windows   monthly: pre 18, "immediate" months 1-3 after onset (lag 1, post 3), "delayed" months 6-11 (lag 6, post 6);
--             weekly deaths: pre 12, "immediate" weeks 1-4 (lag 1, post 4), "delayed" weeks 5-12 (lag 5, post 8)
--   families  the b1 hazard set (storm, hurricane, heat, cold, flood, wildfire, quake)
--   rule      unchanged 6.3.4: split 2024-01-01, regime purge, decoys, MDE gate, clean-control mask, BH within batch;
--             and, as for b4/b5, a confirmation is published only if the held-out events also pass the seasonal
--             robustness check (median in-time p of held-out events), else it is withheld.

-- source registry (att_ingest rejects unknown sources)
insert into ripples.att_sources(source, family, channel, tier, grade, grain, value_kind, enabled, quality, policy_d1, hosts,
  spacing_ms, per_run_cap, history_from, needs_secret, robots_required, engine_channel, attribution, license_note, reason)
values ('cdc.deaths', 'cdc', 'institutional', 'ship', 'green', 'week', 'count', true, 1, false, array['data.cdc.gov'],
  2000, 2, '2014-01-01', null, true, null,
  'Centers for Disease Control and Prevention, National Center for Health Statistics: weekly counts of deaths by state (3yf8-kanr, r8kw-7aab)',
  'Public domain (U.S. government); cite CDC/NCHS',
  'ENGINE 6.3 b6: weekly all-cause deaths by state (keyless Socrata API). NYC folded into NY. Recent 8 weeks never ingested (reporting lag).')
on conflict (source) do nothing;

-- panels
do $$ declare def text;
  a text := '{"source":"fred.state","metric":"nonfarm","geo_kind":"state","agg":"month","value_kind":"level"}';
  b text := a || ',
    {"source":"fred.state","metric":"srvo","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"eduh","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"fire","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"govt","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"pbsv","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"trad","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"mfg","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"cdc.deaths","metric":"all","geo_kind":"state","agg":"week","value_kind":"count","weekly":true}';
begin
  def := pg_get_functiondef('ripples.att_fx63_panel_spec()'::regprocedure);
  if position('"cdc.deaths"' in def) > 0 then return; end if;
  if (length(def) - length(replace(def, a, ''))) / length(a) <> 1 then raise exception 'panel_spec anchor'; end if;
  execute replace(def, a, b);
end $$;

do $$ declare def text;
  a text := $a$when 'fred.state:nonfarm_m' then 'total jobs in the state (nonfarm)'$a$;
  b text := a || $b$
    when 'fred.state:srvo_m' then 'state "other services" jobs (repair & maintenance, personal care, laundry)'
    when 'fred.state:eduh_m' then 'state private education & health jobs'
    when 'fred.state:fire_m' then 'state financial activities jobs (banking, insurance, real estate)'
    when 'fred.state:govt_m' then 'state government jobs (federal, state and local)'
    when 'fred.state:pbsv_m' then 'state professional & business services jobs (incl. temp help, remediation)'
    when 'fred.state:trad_m' then 'state trade, transportation & utilities jobs'
    when 'fred.state:mfg_m' then 'state manufacturing jobs'
    when 'cdc.deaths:all_w' then 'deaths from all causes in the state (weekly)'$b$;
begin
  def := pg_get_functiondef('ripples.att_fx63_outcome_label(text,text)'::regprocedure);
  if position('cdc.deaths:all_w' in def) > 0 then return; end if;
  if (length(def) - length(replace(def, a, ''))) / length(a) <> 1 then raise exception 'outcome_label anchor'; end if;
  execute replace(def, a, b);
end $$;

do $$ declare def text;
  a text := $a$('b5', 'fred.state', 'dom_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]')) p(pset$a$;
  b text := $b$('b5', 'fred.state', 'dom_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'srvo_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'eduh_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'fire_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'govt_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'pbsv_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'trad_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'fred.state', 'mfg_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b6', 'cdc.deaths', 'all_w', 'state', 'health', '[[12,4,1,"immediate"],[12,8,5,"delayed"]]')) p(pset$b$;
begin
  def := pg_get_functiondef('ripples.att_fx63_grid_spec(text)'::regprocedure);
  if position('''b6''' in def) > 0 then return; end if;
  if (length(def) - length(replace(def, a, ''))) / length(a) <> 1 then raise exception 'grid_spec anchor'; end if;
  execute replace(def, a, b);
end $$;

update ripples.att_config set value = jsonb_set(value, '{panel_from}', coalesce(value -> 'panel_from', '{}'::jsonb) || '{
  "fred.state:srvo":"2000-01-01","fred.state:eduh":"2000-01-01","fred.state:fire":"2000-01-01","fred.state:govt":"2000-01-01",
  "fred.state:pbsv":"2000-01-01","fred.state:trad":"2000-01-01","fred.state:mfg":"2000-01-01","cdc.deaths:all":"2014-01-01"}'::jsonb)
 where key = 'engine63';

-- story layer: plain names for the new outcomes (obvious_for = where the link is expected by mechanism)
insert into ripples.att_plain_groups(group_key, name, short, noun, node_regex, domain, sort, obvious_for) values
  ('deaths', 'Deaths', 'Deaths', 'deaths', '^cdc\.deaths:', 'health', 200, '^hazard\.(heat|cold)'),
  ('repairjobs', 'Repair & personal-service jobs', 'Repair jobs', 'repair and personal-service jobs', '^fred\.state:srvo', 'jobs', 210, null),
  ('carejobs', 'Health-care & education jobs', 'Care jobs', 'health-care and education jobs', '^fred\.state:eduh', 'jobs', 211, null),
  ('financejobs', 'Finance & insurance jobs', 'Finance jobs', 'finance and insurance jobs', '^fred\.state:fire', 'jobs', 212, null),
  ('govjobs', 'Government jobs', 'Gov’t jobs', 'government jobs', '^fred\.state:govt', 'jobs', 213, null),
  ('bizjobs', 'Business-services jobs', 'Services jobs', 'business-services jobs (temp help, cleanup)', '^fred\.state:pbsv', 'jobs', 214, null),
  ('tradejobs', 'Retail & transport jobs', 'Retail jobs', 'retail, shipping and utility jobs', '^fred\.state:trad', 'jobs', 215, null),
  ('factoryjobs', 'Factory jobs', 'Factory jobs', 'factory jobs', '^fred\.state:mfg', 'jobs', 216, null)
on conflict (group_key) do update set name = excluded.name, short = excluded.short, noun = excluded.noun, node_regex = excluded.node_regex,
  domain = excluded.domain, obvious_for = excluded.obvious_for;

-- collection: FRED drain now covers 4 + 3 + 7 series x 51 states = 561 ids (was 204); CDC deaths once a day
select cron.unschedule('att-downstream-drain');
select cron.schedule('att-downstream-drain', '1-59/6 * * * *', $c$
  select public.call_collector('att-downstream', '{}'::jsonb)
   where coalesce((select count(*) from ripples.att_state s, jsonb_object_keys(coalesce(s.v -> 'fetched', '{}'::jsonb)) k where s.k = 'econ.fred.downstream'), 0)
       + coalesce((select jsonb_array_length(coalesce(s.v -> 'missing', '[]'::jsonb)) from ripples.att_state s where s.k = 'econ.fred.downstream'), 0) < 561
$c$);
select cron.schedule('att-downstream-cdc', '23 15 * * *', $c$ select public.call_collector('att-downstream', '{"params":{"mode":"cdc"}}'::jsonb) $c$);

-- pre-registration (ledger)
select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'fx63_batch', 'batch', 'fx63-b6-unexpected', 'stage', 'pre-registration', 'method', '6.3.4',
  'grid_spec_sha256', encode(extensions.digest(ripples._canon(ripples.att_fx63_grid_spec('b6'))::text, 'sha256'), 'hex'),
  'note', 'sixth blind batch ("unexpected places"), declared before any b6 panel is built or any b6 test is run (collection not yet started): '
       || 'state monthly panels fred.state srvo_m / eduh_m / fire_m / govt_m / pbsv_m / trad_m / mfg_m (BLS CES supersectors via FRED/ALFRED, first releases, requested from 2000-01; '
       || 'the start is whatever first-release vintages exist, disclosed before freeze) and weekly cdc.deaths all_w (CDC/NCHS all-cause deaths by state, 2014+, last 8 weeks before data_as_of never ingested); '
       || '7 hazard families x 8 outcomes x 2 windows (monthly: immediate = months 1-3, pre 18/post 3/lag 1; delayed = months 6-11, pre 18/post 6/lag 6; '
       || 'weekly deaths: immediate = weeks 1-4, pre 12/post 4/lag 1; delayed = weeks 5-12, pre 12/post 8/lag 5) = 112 variants; same split 2024-01-01, '
       || 'regime purge, selection rule, decoys, MDE gate and clean-control mask as fx63-b4-longhistory; any confirmation must also pass the seasonal robustness check '
       || '(median in-time p of held-out events) to be published, else withheld'),
  ripples.att_fx63_grid_spec('b6'));
