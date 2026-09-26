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
      ('b3', 'fred.state', 'leih_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b4', 'fred.state', 'nonfarm_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b4', 'fred.state', 'cons_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b4', 'fred.state', 'bppriv_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b4', 'fred.state', 'leih_m', 'state', 'labor', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b5', 'fred.state', 'listings_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b5', 'fred.state', 'newlist_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]'),
      ('b5', 'fred.state', 'dom_m', 'state', 'housing', '[[18,3,1,"immediate"],[18,6,6,"delayed"]]')) p(pset, source, metric, geo_kind, dom, variants))
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

-- b3 outcome (ledger 1195): not testable. Every exploration event had a degenerate in-time null (11-12 distinct
-- pseudo-onsets): monthly grain x 18-month pre-window x data from 2016 x regime purge. Rows purged (ledger 1196).
--
-- b4 (long-history re-run, pre-registered before the history is extended): the four outcomes FRED carries back to
-- 1990 (nonfarm, construction jobs, private housing permits, leisure & hospitality jobs), state monthly panels
-- extended to 2000-01 so the in-time placebo has ~3x more pseudo-onsets; same families, same windows as b3.
-- The Realtor.com housing outcomes (from 2016 only) move to the in-space-inference batch (option 2).
-- Collection: att_config econ.fred_state_from = 2000-01-01; att-downstream nonfarm observation_start 2000-01-01.
--
-- b5 / method 6.3.5-m (pre-registered at ledger 1198, before the batch is frozen): in-space fallback for monthly panels
-- whose in-time null is degenerate, ONLY for batches listed in engine63.space_fallback_batches (["fx63-b5-housing-space"]).
-- Applied to the live bodies as anchor-checked, idempotent patches (same pattern as att_fx63_hook_install):
--   att_fx_calc: collects the in-space permutation draws it already computes and returns them as 'space_d' (additive:
--     no existing output or random draw changes).
--   att_fx63_step: in the month-grain degenerate branch, for listed batches with >= space_min_draws (20) draws:
--     med = median(space_d), se = max(1.4826*MAD, se_floor), z = (d - med)/se, placebo_d := space_d, note 'in-space null'.
update ripples.att_config set value = value || '{"space_fallback_batches":["fx63-b5-housing-space"],"space_min_draws":20}'::jsonb
 where key = 'engine63';

do $$ declare def text; sig text := 'ripples.att_fx_calc(double precision[],smallint[],date[],text[],text,text[],date,integer,integer,integer,boolean,double precision,jsonb)';
  a1 text := 'pos int; tmp int; pool int[]; j int;'; b1 text := 'pos int; tmp int; pool int[]; j int; sdr float8[] := ''{}''; /* ENGINE 6.3.5-m: in-space draws */';
  a2 text := 'ns := ns + 1;'; b2 text := 'ns := ns + 1; sdr := sdr || x[1];';
  a3 text := '''n_space'', ns,'; b3 text := '''n_space'', ns, ''space_d'', to_jsonb(sdr),';
begin
  select pg_get_functiondef(sig::regprocedure) into def;
  if position('ENGINE 6.3.5-m' in def) > 0 then return; end if;
  if (length(def)-length(replace(def,a1,'')))/length(a1) <> 1 or (length(def)-length(replace(def,a2,'')))/length(a2) <> 1
     or (length(def)-length(replace(def,a3,'')))/length(a3) <> 1 then raise exception 'att_fx_calc anchors'; end if;
  execute replace(replace(replace(def,a1,b1),a2,b2),a3,b3);
end $$;

do $$ declare def text;
  a text := $a$if n_dist < mind then j := j || jsonb_build_object('se', null, 'med', null, 'note', 'degenerate null (' || n_dist || ' distinct pseudo-onsets)'); end if;$a$;
  b text := $b$if n_dist < mind then
          -- ENGINE 6.3.5-m (33_att_engine_63_b3_downstream): in-space fallback, only for batches listed in engine63.space_fallback_batches.
          if split_part(g.batch, '/', 1) in (select jsonb_array_elements_text(coalesce(cfg -> 'space_fallback_batches', '[]'::jsonb)))
             and jsonb_array_length(coalesce(j -> 'space_d', '[]'::jsonb)) >= coalesce((cfg ->> 'space_min_draws')::int, 20) then
            j := j || (select jsonb_build_object('med', m, 'se', greatest(1.4826 * mad, coalesce((c ->> 'se_floor')::float8, 0.005)),
                                                 'z', ((j ->> 'd')::float8 - m) / greatest(1.4826 * mad, coalesce((c ->> 'se_floor')::float8, 0.005)),
                                                 'placebo_d', j -> 'space_d',
                                                 'note', 'in-space null (' || jsonb_array_length(j -> 'space_d') || ' draws; in-time degenerate: ' || n_dist || ' distinct pseudo-onsets)')
                         from (select m, (select percentile_cont(0.5) within group (order by abs(x::float8 - m)) from jsonb_array_elements_text(j -> 'space_d') x) mad
                                 from (select percentile_cont(0.5) within group (order by x::float8) m from jsonb_array_elements_text(j -> 'space_d') x) q) q2);
          else
            j := j || jsonb_build_object('se', null, 'med', null, 'note', 'degenerate null (' || n_dist || ' distinct pseudo-onsets)');
          end if;
        end if;$b$;
begin
  select pg_get_functiondef('ripples.att_fx63_step(integer,text[])'::regprocedure) into def;
  if position('ENGINE 6.3.5-m' in def) > 0 then return; end if;
  if (length(def)-length(replace(def,a,'')))/length(a) <> 1 then raise exception 'att_fx63_step anchor'; end if;
  execute replace(def,a,b);
end $$;
-- grid set b5 (listings_m, newlist_m, dom_m; same windows) is in att_fx63_grid_spec(p_set) as applied live.

-- b5 outcome (ledger 1200 confirm freeze, 1201 calibration, 1203 withheld): 2 pairs passed the pre-registered rule
-- (wildfire -> days on market, months 1-3; wildfire -> new listings, months 6-11; decoys 0 of 336 decoy grids confirmed)
-- but FAIL a post-hoc seasonal robustness check (same states, same calendar months, other years look alike: median
-- in-time p 0.48 / 0.52). The in-space null does not adjust for region-specific seasonality. Batch status 'withheld',
-- method 6.3.5-m suspended (space_fallback_batches = []). A seasonally de-meaned in-space null is required before reuse.
update ripples.att_config set value = value || '{"space_fallback_batches":[]}'::jsonb where key = 'engine63';

-- public reads must never surface a withheld / not-testable / superseded batch (patched live, anchor-checked):
do $$ declare r record; def text; a text := 'where v.decoy_set = 0';
  b text := 'where v.decoy_set = 0 and not exists (select 1 from ripples.att_fx63_batch xb where xb.batch = v.batch and xb.status in (''withheld'', ''not testable'', ''superseded''))';
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('rm_patterns63', 'rm_hunches', 'rm_kill_list63') loop
    def := pg_get_functiondef(r.oid);
    continue when position('xb.status in' in def) > 0;
    if (length(def) - length(replace(def, a, ''))) / length(a) <> 1 then raise exception 'anchor count in %', r.oid::regprocedure; end if;
    execute replace(def, a, b);
  end loop;
end $$;

-- Supabase Pro (2026-09-26): ingest cap raised to 6000 MB; b-batch space guard at 5800 MB.
update ripples.att_config set value = to_jsonb(6000) where key = 'db_cap_mb';
