-- Engine 6.3 batch b3: downstream outcomes (2026-09-26).
--
-- Owner direction: the point of Ripple Map is what happens AFTER the first-order effect (storm → less power is the
-- engine's calibration, not the product). b1 tested state jobs/permits only 0–3 months out, too early for rebuilding,
-- housing-market and labour-market knock-ons. b3 adds housing-inventory and total-jobs panels (collected by the
-- att-downstream edge function into source 'fred.state') and re-tests the slow outcomes over two longer windows,
-- through the same split-sample exploration (< split date) → held-out confirmation pipeline as b1/b2.
--
-- Pre-registered here, before any b3 exploration result exists:
--   outcomes  fred.state listings_m (Realtor.com active listings), newlist_m (new listings), dom_m (median days on
--             market), nonfarm_m (total nonfarm jobs), cons_m (construction jobs), bppriv_m (private housing permits),
--             leih_m (leisure & hospitality jobs)
--   windows   monthly grain, 18 pre-months; "immediate" = months 1–3 after onset (lag 1, post 3);
--             "delayed" = months 6–11 (lag 6, post 6)
--   families  the b1 hazard set (storm, hurricane, heat, cold, flood, wildfire, quake)

create or replace function ripples.att_fx63_panel_spec()
 returns jsonb language sql immutable set search_path to '' as $function$
  select '[
    {"source":"fema.decl","metric":"n","geo_kind":"state","agg":"week","value_kind":"count"},
    {"source":"eia.930","metric":"demand","geo_kind":"ba","agg":"week","value_kind":"level"},
    {"source":"eia.930","metric":"ng_solar","geo_kind":"ba","agg":"week","value_kind":"level","weekly":true},
    {"source":"eia.930","metric":"ng_wind","geo_kind":"ba","agg":"week","value_kind":"level","weekly":true},
    {"source":"eia.930","metric":"sub_demand","geo_kind":"sub","agg":"week","value_kind":"level","weekly":true},
    {"source":"fred.state","metric":"leih","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"cons","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"ur","geo_kind":"state","agg":"month","value_kind":"rate"},
    {"source":"fred.state","metric":"bppriv","geo_kind":"state","agg":"month","value_kind":"count"},
    {"source":"fred.state","metric":"listings","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"newlist","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"dom","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"nonfarm","geo_kind":"state","agg":"month","value_kind":"level"}
  ]'::jsonb
$function$;

create or replace function ripples.att_fx63_outcome_label(p_source text, p_metric text)
 returns text language sql immutable set search_path to '' as $function$
  select case p_source || ':' || p_metric
    when 'fema.decl:n_w' then 'FEMA disaster declarations in the state (weekly)'
    when 'eia.930:demand_w' then 'regional grid electricity demand (weekly)'
    when 'eia.930:ng_solar_w' then 'regional grid solar generation (weekly)'
    when 'eia.930:ng_wind_w' then 'regional grid wind generation (weekly)'
    when 'eia.930:sub_demand_w' then 'grid sub-region electricity demand (weekly)'
    when 'fred.state:leih_m' then 'state leisure & hospitality employment'
    when 'fred.state:cons_m' then 'state construction employment'
    when 'fred.state:ur_m' then 'state unemployment rate'
    when 'fred.state:bppriv_m' then 'state private housing permits'
    when 'fred.state:listings_m' then 'homes for sale in the state (active listings)'
    when 'fred.state:newlist_m' then 'new home listings in the state'
    when 'fred.state:dom_m' then 'days a home sits on the market in the state (median)'
    when 'fred.state:nonfarm_m' then 'total jobs in the state (nonfarm)'
    else ripples.att_fx_outcome_label(p_source, p_metric) end
$function$;

create or replace function ripples.att_fx63_grid_spec(p_set text)
 returns jsonb language sql immutable set search_path to '' as $function$
  with fam as (select * from (values
      ('hazard.storm', null::text, true), ('hazard.storm', 'hurricane', true), ('hazard.heat', null, false), ('hazard.cold', null, true),
      ('hazard.flood', null, true), ('hazard.wildfire', null, true), ('hazard.quake', null, true)) f(family, sub, fema_defined)),
  pan as (select * from (values
      ('b1', 'dol.claims', 'ic', 'state', 'labor', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'::jsonb),
      ('b1', 'dol.claims', 'cw', 'state', 'labor', '[[8,4,1,"immediate"],[8,4,5,"delayed"]]'),
      ('b1', 'census.bfs', 'ba', 'state', 'business', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'),
      ('b1', 'eia.930', 'demand', 'ba', 'power', '[[28,7,0,"immediate"],[28,14,7,"delayed"]]'),
      ('b1', 'eia.930', 'demand_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b1', 'fema.decl', 'n_w', 'state', 'government', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b1', 'fred.state', 'leih_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'cons_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'ur_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'bppriv_m', 'state', 'housing', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b2', 'eia.930', 'ng_solar_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b2', 'eia.930', 'ng_wind_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b2', 'eia.930', 'sub_demand_w', 'sub', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b3', 'fred.state', 'listings_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'newlist_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'dom_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'nonfarm_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'cons_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'bppriv_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b3', 'fred.state', 'leih_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]')) p(pset, source, metric, geo_kind, dom, variants))
  select jsonb_agg(jsonb_build_object('family', f.family, 'sub', f.sub, 'source', p.source, 'metric', p.metric, 'geo_kind', p.geo_kind,
                                      'de', 'hazard', 'do', p.dom, 'variants', p.variants,
                                      'definitional', (p.source = 'fema.decl' and f.fema_defined),
                                      'w', case when p.source = 'fema.decl' and f.fema_defined then 0 else 1 end)
                   order by f.family, f.sub nulls first, p.source, p.metric)
  from fam f cross join pan p where p.pset = p_set and (p_set <> 'b2' or f.family <> 'hazard.quake')
$function$;

-- collection: drain every 6 minutes until all 204 ids are fetched or recorded missing, then a daily refresh
select cron.schedule('att-downstream-drain', '1-59/6 * * * *', $c$
  select public.call_collector('att-downstream', '{}'::jsonb)
   where coalesce((select count(*) from ripples.att_state s, jsonb_object_keys(coalesce(s.v -> 'fetched', '{}'::jsonb)) k where s.k = 'econ.fred.downstream'), 0)
       + coalesce((select jsonb_array_length(coalesce(s.v -> 'missing', '[]'::jsonb)) from ripples.att_state s where s.k = 'econ.fred.downstream'), 0) < 204
$c$);
select cron.schedule('att-downstream-daily', '17 14 * * *', $c$ select public.call_collector('att-downstream', '{}'::jsonb) $c$);
