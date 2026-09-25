-- Migration: att_engine_freeze (WS-B, Ripple Map v6, 2026-09-25)
-- ENGINE_SPEC §1.2–1.3 (nodes, events, decoys), §2 (candidate generation, priors, caps, BH weights, looks, VOI, freeze hash),
-- §5.6.6 (register rows) and the att_ledger chain (§10.6). Everything runs before any post-onset statistic is read.
-- Depends on 20_att_engine_zvec.sql. Family mappers / templates / edges are read from WS-A's tables in these formats:
--   att_families.mapper      : [{"node":"tsa.pax:checkpoint","sign":-1,"template":"storm_air_travel"},
--                               {"node_pattern":"eia.930:{}","meta_key":"ba","sign":1,"template":"heat_grid_demand"}]
--   att_mech_templates.target_pattern : {"node":"…"} | {"node_pattern":"src:{}","meta_key":"…"} | {"source":"npm.dl","keys_from":"topic_keys"}
--   att_mech_edges           : from_node 'Q…' or 'family:hazard.storm'; to_node 'Q…' or 'source:key'; etype MAP/WD/MECH; sign; strength; meta.demean

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Ledger (chained from a stored genesis hash — the ripples.ledger head at cutover, kept in att_state 'engine.ledger.genesis';
--    extensions.digest exactly as SPEC §10). Fix 4b: every freeze payload is kept verbatim in att_freeze_snapshots.
-- ---------------------------------------------------------------------------------------------------------------------
-- (6)(7) ledger genesis + freeze snapshots
create table if not exists ripples.att_freeze_snapshots (
  payload_hash text primary key, seq bigint not null, day date not null, payload jsonb not null, created_at timestamptz not null default now());
alter table ripples.att_freeze_snapshots enable row level security;
revoke all on table ripples.att_freeze_snapshots from anon, authenticated, public;
insert into ripples.att_state(k, v)
select 'engine.ledger.genesis', jsonb_build_object('prev_hash', prev_hash, 'seq', seq, 'noted', now()) from ripples.att_ledger order by seq limit 1
on conflict (k) do nothing;


create or replace function ripples.att_ledger_head() returns text
language sql stable set search_path = '' as $$
  select coalesce((select chain_hash from ripples.att_ledger order by seq desc limit 1),
                  (select v ->> 'prev_hash' from ripples.att_state where k = 'engine.ledger.genesis'),
                  repeat('0', 64))
$$;

create or replace function ripples.att_ledger_append(p_day date, p_kind text, p_ref jsonb, p_payload jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare ph text; prev text; ch text; v_seq bigint;
begin
  lock table ripples.att_ledger in share row exclusive mode;
  ph := encode(extensions.digest(ripples._canon(p_payload)::text, 'sha256'), 'hex');
  prev := ripples.att_ledger_head();
  if not exists (select 1 from ripples.att_ledger) then
    insert into ripples.att_state(k, v) values ('engine.ledger.genesis', jsonb_build_object('prev_hash', prev, 'noted', now())) on conflict (k) do nothing;
  end if;
  ch := encode(extensions.digest(prev || ph, 'sha256'), 'hex');
  insert into ripples.att_ledger(day, kind, ref, payload_hash, prev_hash, chain_hash)
  values (p_day, p_kind, coalesce(p_ref, '{}'::jsonb), ph, prev, ch) returning seq into v_seq;
  -- every freeze payload is kept verbatim, so a batch can be shown unchanged later (not only re-hashed)
  if p_kind = 'freeze' then
    insert into ripples.att_freeze_snapshots(payload_hash, seq, day, payload) values (ph, v_seq, p_day, p_payload) on conflict (payload_hash) do nothing;
  end if;
  return v_seq;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Nodes and measurement bundles
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_slugify(p text) returns text
language sql immutable strict set search_path = '' as $$
  select btrim(regexp_replace(lower(regexp_replace(p, '[^A-Za-z0-9]+', '-', 'g')), '-+', '-', 'g'), '-')
$$;

-- The topic row standing for a node ('Q…' → the topic with that qid; 'source:key' → a node topic, created on demand)
create or replace function ripples.att_node_topic(p_node text, p_label text default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_src text; v_key text; v_domain text;
begin
  if p_node ~ '^Q[0-9]+$' then
    select topic_id into v_id from ripples.att_topics where qid = p_node;
    return v_id;
  end if;
  select topic_id into v_id from ripples.att_topics where label_key = 'node:' || p_node;
  if v_id is not null then return v_id; end if;
  v_src := split_part(p_node, ':', 1); v_key := substr(p_node, length(v_src) + 2);
  if not exists (select 1 from ripples.att_sources where source = v_src) then return null; end if;
  select domain into v_domain from ripples.att_engine_source_map where source = v_src;
  insert into ripples.att_topics(qid, label_key, label, title_en, lang, category, status, in_panel, origin, meta)
  values (null, 'node:' || p_node, coalesce(p_label, v_key), null, 'en', coalesce(v_domain, 'other'), 'panel', false, 'cascade',
          jsonb_build_object('node', p_node, 'source', v_src, 'key', v_key))
  on conflict (label_key) do nothing returning topic_id into v_id;
  if v_id is null then select topic_id into v_id from ripples.att_topics where label_key = 'node:' || p_node; end if;
  return v_id;
end $$;

-- (Re)build the bundle of a node: its series across channels (MONEY excluded; __total__ excluded)
create or replace function ripples.att_node_bundle(p_node text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0; v_src text; v_key text; v_topic bigint;
begin
  delete from ripples.att_node_series where node = p_node;
  if p_node ~ '^Q[0-9]+$' then
    select topic_id into v_topic from ripples.att_topics where qid = p_node;
    insert into ripples.att_node_series(node, series_id, channel)
    select p_node, s.series_id, ripples.att_series_channel(s.series_id)
    from ripples.att_series s join ripples.att_sources src on src.source = s.source
    where s.topic_id = v_topic and s.key <> '__total__' and src.enabled
      and ripples.att_series_channel(s.series_id) not in ('MONEY')
    on conflict do nothing;
  else
    v_src := split_part(p_node, ':', 1); v_key := substr(p_node, length(v_src) + 2);
    insert into ripples.att_node_series(node, series_id, channel)
    select p_node, s.series_id, ripples.att_series_channel(s.series_id)
    from ripples.att_series s join ripples.att_sources src on src.source = s.source
    where s.source = v_src and s.key = v_key and src.enabled and ripples.att_series_channel(s.series_id) not in ('MONEY')
    on conflict do nothing;
  end if;
  get diagnostics n = row_count;
  return n;
end $$;

-- κ of a whole source (median κ over its zvec rows); used for the P-COM / linkage κ ≥ 0.3 rules
create or replace function ripples.att_source_kappa(p_source text) returns real
language sql stable set search_path = '' as $$
  select coalesce((select percentile_cont(0.5) within group (order by z.kappa) from ripples.att_zvec z join ripples.att_series s using (series_id)
                   where s.source = p_source and s.key <> '__total__'), 0)::real
$$;

-- Deterministic family assignment (ENGINE §1.3): meta.family override → calendar match → P31 class map → discovery source → category
create or replace function ripples.att_family_of(p_topic bigint, p_onset date, p_discovery text default null) returns text
language plpgsql stable set search_path = '' as $$
declare t record; f text; p31 text[];
begin
  select * into t from ripples.att_topics where topic_id = p_topic;
  if not found then return 'other'; end if;
  f := t.meta ->> 'family';
  if f is not null and exists (select 1 from ripples.att_families where family = f) then return f; end if;
  select c.family into f from ripples.att_family_calendar c
   where c.qid = t.qid and c.scheduled_for between p_onset - 3 and p_onset + 3 order by abs(c.scheduled_for - p_onset) limit 1;
  if f is not null then return f; end if;
  select coalesce(array_agg(x), '{}') into p31 from jsonb_array_elements_text(coalesce(t.meta -> 'p31', '[]'::jsonb)) x;
  if cardinality(p31) = 0 and t.qid is not null then select coalesce(a.p31, '{}') into p31 from ripples.articles a where a.qid = t.qid; end if;
  select fc.family into f from ripples.att_family_classes fc where fc.class_qid = any(p31) order by fc.class_qid limit 1;
  if f is not null and exists (select 1 from ripples.att_families where family = f) then return f; end if;
  if p_discovery is not null then
    f := case when p_discovery in ('fema','iem','gdacs','usgs') then 'hazard.storm'
              when p_discovery in ('hf','github','npm') then 'tech.model_release'
              when p_discovery in ('polymarket','kalshi') then 'policy.decision' end;
    if f is not null and exists (select 1 from ripples.att_families where family = f) then return f; end if;
  end if;
  f := case when t.category like 'people%' then 'person' when t.category = 'film_tv' then 'media.film'
            when t.category = 'games' then 'media.game' else 'other' end;
  if exists (select 1 from ripples.att_families where family = f) then return f; end if;
  return 'other';
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Seed families (minimal; WS-A owns the full mappers and overwrites with its own rows)
-- ---------------------------------------------------------------------------------------------------------------------
insert into ripples.att_families(family, label, scheduled, mapper) values
 ('hazard.storm','Storm',false,'[{"node":"tsa.pax:checkpoint","sign":-1,"template":"storm_air_travel"},{"node":"fema.decl:DR","sign":1,"template":"storm_fema_declaration"},{"node":"fema.decl:it:hurricane","sign":1,"template":"storm_fema_declaration"},{"node":"iem.warn:__total__","sign":1,"template":"storm_nws_warnings"},{"node":"mta.ridership:subway","sign":-1,"template":"storm_transit_dip","geo":"NYC"},{"node_pattern":"eia.930:{}","meta_key":"ba","sign":-1,"template":"storm_grid_demand"},{"node_pattern":"fred:{}ICLAIMS","meta_key":"state","sign":1,"template":"storm_claims"}]'),
 ('hazard.flood','Flood',false,'[{"node":"fema.decl:it:flood","sign":1,"template":"storm_fema_declaration"},{"node":"iem.warn:FF.W","sign":1,"template":"storm_nws_warnings"},{"node":"iem.warn:FA.W","sign":1,"template":"storm_nws_warnings"}]'),
 ('hazard.wildfire','Wildfire',false,'[{"node":"fema.decl:it:fire","sign":1,"template":"storm_fema_declaration"},{"node":"fema.decl:FM","sign":1,"template":"storm_fema_declaration"}]'),
 ('hazard.heat','Heat wave',false,'[{"node_pattern":"eia.930:{}","meta_key":"ba","sign":1,"template":"heat_grid_demand"},{"node":"eia.prices:henry_hub","sign":1,"template":"heat_henry_hub"},{"node":"iem.warn:EH.W","sign":1,"template":"heat_advisories"}]'),
 ('hazard.cold','Cold snap',false,'[{"node_pattern":"eia.930:{}","meta_key":"ba","sign":1,"template":"cold_grid_demand"},{"node":"eia.prices:henry_hub","sign":1,"template":"cold_henry_hub"}]'),
 ('hazard.quake','Earthquake',false,'[{"node":"fema.decl:it:earthquake","sign":1,"template":"storm_fema_declaration"},{"node":"usgs.eq:felt","sign":1,"template":"quake_felt_reports"}]'),
 ('tech.model_release','AI model release',true,'[{"source":"npm.dl","keys_from":"topic_keys","sign":1,"template":"model_release_packages"},{"source":"pypi.dl","keys_from":"topic_keys","sign":1,"template":"model_release_packages"},{"source":"hn.algolia","keys_from":"topic_keys","sign":1,"template":"model_release_hn"},{"source":"se.api","keys_from":"topic_keys","sign":1,"template":"software_release_se"}]'),
 ('tech.software_release','Software release',true,'[{"source":"npm.dl","keys_from":"topic_keys","sign":1,"template":"model_release_packages"},{"source":"se.api","keys_from":"topic_keys","sign":1,"template":"software_release_se"}]'),
 ('policy.macro_release','Scheduled macro release',true,'[{"node":"fred:DGS2","sign":0,"template":"macro_rates"},{"node":"fred:DGS10","sign":0,"template":"macro_rates"},{"node":"fred:T10YIE","sign":0,"template":"macro_rates"},{"node":"fred:DEXUSEU","sign":0,"template":"macro_rates"},{"node":"fred:DTWEXBGS","sign":0,"template":"macro_rates"}]'),
 ('policy.decision','Policy decision',false,'[{"source":"poly.mkt","keys_from":"topic_keys","sign":0,"template":"decision_prediction_market"}]'),
 ('media.film','Film',true,'[]'), ('media.game','Game',true,'[{"source":"steamspy","keys_from":"topic_keys","sign":1,"template":"game_players"}]'),
 ('media.series','Series',true,'[{"source":"anilist","keys_from":"topic_keys","sign":1,"template":"series_fandom"}]'),
 ('person','Person',false,'[]'), ('other','Other',false,'[]')
on conflict (family) do nothing;

insert into ripples.att_mech_templates(template, family, target_pattern, sign, channel, l_days, rationale, version) values
 ('storm_air_travel','hazard.storm','{"node":"tsa.pax:checkpoint"}',-1,'PHYS',7,'Storm warnings → cancelled and avoided flights','6.0'),
 ('storm_transit_dip','hazard.storm','{"node":"mta.ridership:subway","geo":"NYC"}',-1,'PHYS',7,'Storm → closures and stay-home days on transit (NYC-area storms only)','6.0'),
 ('storm_fema_declaration','hazard.storm','{"node":"fema.decl:DR"}',1,'INST',90,'Storm → federal disaster declaration','6.0'),
 ('storm_nws_warnings','hazard.storm','{"node":"iem.warn:__total__"}',1,'INST',7,'Storm → NWS warning issuance','6.0'),
 ('storm_claims','hazard.storm','{"node_pattern":"fred:{}ICLAIMS","meta_key":"state"}',1,'JOBS',28,'Storm → initial jobless claims in the affected state','6.0'),
 ('storm_grid_demand','hazard.storm','{"node_pattern":"eia.930:{}","meta_key":"ba"}',-1,'PHYS',7,'Storm → outages and lower grid demand in the affected balancing authority','6.0'),
 ('heat_grid_demand','hazard.heat','{"node_pattern":"eia.930:{}","meta_key":"ba"}',1,'PHYS',7,'Heat → air-conditioning load on the regional grid','6.0'),
 ('heat_henry_hub','hazard.heat','{"node":"eia.prices:henry_hub"}',1,'ECON',4,'Heat → gas burn for power → Henry Hub spot','6.0'),
 ('cold_grid_demand','hazard.cold','{"node_pattern":"eia.930:{}","meta_key":"ba"}',1,'PHYS',7,'Cold → heating load on the regional grid','6.0'),
 ('cold_henry_hub','hazard.cold','{"node":"eia.prices:henry_hub"}',1,'ECON',4,'Cold → heating gas demand → Henry Hub spot','6.0'),
 ('model_release_packages','tech.model_release','{"source":"npm.dl","keys_from":"topic_keys"}',1,'BLD',14,'Model release → SDK package downloads','6.0'),
 ('model_release_hn','tech.model_release','{"source":"hn.algolia","keys_from":"topic_keys"}',1,'SOC',2,'Model release → builder discussion','6.0'),
 ('software_release_se','tech.software_release','{"source":"se.api","keys_from":"topic_keys"}',1,'SOC',2,'Software release → Stack Exchange questions','6.0'),
 ('macro_rates','policy.macro_release','{"node":"fred:DGS10"}',0,'ECON',4,'Macro release → rates and FX reprice','6.0'),
 ('decision_prediction_market','policy.decision','{"source":"poly.mkt","keys_from":"topic_keys"}',0,'PM',4,'Policy decision → prediction-market repricing','6.0'),
 ('wildfire_air_quality','hazard.wildfire','{"node":"iem.warn:__total__"}',1,'INST',7,'Wildfire → air-quality and red-flag warnings','6.0')
on conflict (template) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. att_pick_events (ENGINE §1.3): 12 real shocks + 8 matched decoys from ripples.seeds, scheduled events from the calendar
-- ---------------------------------------------------------------------------------------------------------------------
-- att_pick_events(p_as_of, p_seed_day): defined in 25_att_engine_ledger.sql (seed-day-tolerant version; the v5 ripples-tick may write
-- the day's seeds under yesterday's as_of). Kept out of this file so no single-argument overload can be recreated.

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Candidate generation and freeze (ENGINE §2)
-- ---------------------------------------------------------------------------------------------------------------------
-- Look schedule per channel (ENGINE §7), relative to the parent onset; look dates are the mornings the look runs
create or replace function ripples.att_look_dates(p_channel text, p_onset date, p_l int) returns date[]
language sql immutable set search_path = '' as $$
  select case
    when p_channel in ('READ','SRCH','SOC','NEWS','TV','PM','ECON') then
      (select array_agg(p_onset + d + 1) from generate_series(1, p_l) d)
    when p_channel = 'PHYS' then array[p_onset + 4, p_onset + 8]
    when p_channel in ('BLD','CONS') then array[p_onset + 8, p_onset + 15]
    when p_channel = 'JOBS' then array[p_onset + 8, p_onset + 15, p_onset + 22, p_onset + 29]
    else array[p_onset + 31, p_onset + 61, p_onset + 91] end
$$;

-- Effective L_c: att_lag_windows (event_type 'any', n ≥ 30) overrides the prior in att_channel_stat
create or replace function ripples.att_l_days(p_channel text) returns int
language sql stable set search_path = '' as $$
  select coalesce((select ceil(l.l_days)::int from ripples.att_lag_windows l where l.channel = p_channel and l.event_type = 'any' and l.n >= 30),
                  (select l_days::int from ripples.att_channel_stat where channel = p_channel), 7)
$$;

-- Prior π_{τ,c}: fitted (tested ≥ 30, family-specific first) under the time split, else the seeded value
create or replace function ripples.att_edge_prior(p_etype text, p_channel text, p_family text) returns real
language sql stable set search_path = '' as $$
  select coalesce(
    (select prior from ripples.att_edge_priors where etype = p_etype and channel = p_channel and family = p_family and not seeded and tested >= 30 order by version desc limit 1),
    (select prior from ripples.att_edge_priors where etype = p_etype and channel = p_channel and family = 'any' and not seeded and tested >= 30 order by version desc limit 1),
    (select prior from ripples.att_edge_priors where etype = p_etype and channel = p_channel and family = 'any' and seeded order by version desc limit 1),
    case p_etype when 'MAP' then 0.20 when 'MECH' then 0.25 when 'WD' then 0.10 when 'WIKI' then 0.15 when 'CS' then 0.15 when 'GK' then 0.10 else 0.10 end)::real
$$;

-- Resolve a mapper / template target item to node ids for an event topic
create or replace function ripples.att_resolve_targets(p_item jsonb, p_topic bigint) returns setof text
language plpgsql stable set search_path = '' as $$
declare v text; meta jsonb;
begin
  if p_item ? 'node' then return next p_item ->> 'node'; return; end if;
  if p_item ? 'node_pattern' and p_item ? 'meta_key' then
    select t.meta into meta from ripples.att_topics t where t.topic_id = p_topic;
    if meta is null then return; end if;
    if jsonb_typeof(meta -> (p_item ->> 'meta_key')) = 'array' then
      for v in select x from jsonb_array_elements_text(meta -> (p_item ->> 'meta_key')) x loop
        return next replace(p_item ->> 'node_pattern', '{}', v);
      end loop;
    elsif meta ? (p_item ->> 'meta_key') then
      return next replace(p_item ->> 'node_pattern', '{}', meta ->> (p_item ->> 'meta_key'));
    end if;
    return;
  end if;
  if p_item ? 'source' and p_item ->> 'keys_from' = 'topic_keys' then
    for v in select distinct k.key from ripples.att_keys k where k.topic_id = p_topic and k.source = p_item ->> 'source' and k.enabled loop
      return next (p_item ->> 'source') || ':' || v;
    end loop;
  end if;
  return;
end $$;

-- Staging row type for candidate generation
create table if not exists ripples.att_cand_stage (
  as_of date not null, event_id bigint not null, role text not null, parent_hop bigint, depth smallint not null default 1,
  u_topic bigint not null, node text not null, path jsonb not null, path_type text not null, sign smallint not null default 0,
  excluded_ch text[] not null default '{}', prior real, onset date not null, template text, rank_in_path int,
  aware real not null default 0, jumps real not null default 1
);

-- Generate the candidate set for one event (any role) into att_cand_stage. p_parent_hop/p_depth for chained expansion.
create or replace function ripples.att_gen_candidates(p_event bigint, p_as_of date, p_parent_hop bigint default null, p_depth int default 1,
                                                       p_from_node text default null, p_onset date default null) returns int
language plpgsql security definer set search_path = '' as $$
declare e record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); caps jsonb; v_from text; v_topic bigint; v_onset date;
        v_qid text; it jsonb; nd text; n int := 0; r record; v_family text; k int; v_kappa real;
begin
  select * into e from ripples.att_events where event_id = p_event;
  if not found then return 0; end if;
  caps := coalesce(cfg -> 'caps', '{}'::jsonb);
  v_from := coalesce(p_from_node, e.qid);
  v_onset := coalesce(p_onset, e.onset);
  v_family := e.family;
  -- the topic that stands for the parent node (for topic_keys / meta lookups)
  v_topic := case when v_from ~ '^Q[0-9]+$' then (select topic_id from ripples.att_topics where qid = v_from) else ripples.att_node_topic(v_from) end;
  if v_topic is null then v_topic := e.topic_id; end if;
  if v_topic is null then return 0; end if;
  v_qid := case when v_from ~ '^Q[0-9]+$' then v_from end;
  -- decoys use their matched real's family mappers (same candidate generation by construction, ENGINE §1.3)

  -- P-MAP: family mapper items + MAP edges from the node / family
  k := 0;
  for it in select x from ripples.att_families f, jsonb_array_elements(f.mapper) x where f.family = v_family loop
    for nd in select * from ripples.att_resolve_targets(it, e.topic_id) loop
      exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MAP','from',v_from,'to',nd,'sign',coalesce((it->>'sign')::int,0),'s',1.0,'template',it->>'template','source','family mapper')),
              'P-MAP', coalesce((it->>'sign')::int, 0), null, v_onset, it->>'template', k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;
  for r in select m.to_node, m.sign, m.strength, m.template, m.meta from ripples.att_mech_edges m
            where m.etype = 'MAP' and m.valid_to is null and m.from_node in (v_from, 'family:' || v_family) order by m.strength desc, m.edge_id loop
    exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
    insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
    values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.to_node,
            jsonb_build_array(jsonb_build_object('type','MAP','from',v_from,'to',r.to_node,'sign',r.sign,'s',r.strength,'template',r.template,'source','map edge','meta',r.meta)),
            'P-MAP', r.sign, null, v_onset, r.template, k, 0, 1);
    k := k + 1; n := n + 1;
  end loop;

  -- P-MECH: mechanism library templates matching the family
  k := 0;
  for r in select t.* from ripples.att_mech_templates t where t.family = v_family order by t.template loop
    for nd in select * from ripples.att_resolve_targets(r.target_pattern, e.topic_id) loop
      exit when k >= coalesce((caps ->> 'P-MECH')::int, 10);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MECH','from',v_from,'to',nd,'sign',r.sign,'s',1.0,'template',r.template,'source','mechanism library v' || r.version,'text',r.rationale)),
              'P-MECH', r.sign, null, v_onset, r.template, k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;

  -- P-WD: Wikidata-property neighbours owning ≥ 1 series with κ ≥ 0.3, plus their MAP targets
  k := 0;
  if v_qid is not null then
    for r in
      select m.to_node, m.prop, m.strength, exists (select 1 from ripples.att_topics t join ripples.att_series s on s.topic_id = t.topic_id
                                                     join ripples.att_zvec z on z.series_id = s.series_id where t.qid = m.to_node and z.kappa >= 0.3) has_series
      from ripples.att_mech_edges m where m.etype = 'WD' and m.valid_to is null and m.from_node = v_qid order by m.strength desc, m.edge_id
    loop
      exit when k >= coalesce((caps ->> 'P-WD')::int, 15);
      if r.has_series then
        insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, rank_in_path, aware, jumps)
        values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.to_node,
                jsonb_build_array(jsonb_build_object('type','WD','from',v_qid,'to',r.to_node,'prop',r.prop,'sign',0,'s',r.strength,'source','Wikidata ' || coalesce(r.prop,''))),
                'P-WD', 0, null, v_onset, k, 0, 0.5);
        k := k + 1; n := n + 1;
      end if;
      for it in select jsonb_build_object('to', m2.to_node, 'sign', m2.sign, 's', m2.strength, 'template', m2.template)
                from ripples.att_mech_edges m2 where m2.etype = 'MAP' and m2.valid_to is null and m2.from_node = r.to_node limit 3 loop
        exit when k >= coalesce((caps ->> 'P-WD')::int, 15);
        insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
        values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, it->>'to',
                jsonb_build_array(jsonb_build_object('type','WD','from',v_qid,'to',r.to_node,'prop',r.prop,'sign',0,'s',r.strength,'source','Wikidata ' || coalesce(r.prop,'')),
                                  jsonb_build_object('type','MAP','from',r.to_node,'to',it->>'to','sign',(it->>'sign')::int,'s',(it->>'s')::real,'template',it->>'template','source','map edge')),
                'P-WD', (it->>'sign')::int, null, v_onset, it->>'template', k, 0, 1);
        k := k + 1; n := n + 1;
      end loop;
    end loop;
  end if;

  -- P-WIKI: SPEC §5.2 beam from ripples.candidates (live outlinks; the P-WIKI pipeline keeps writing there); attention-only
  k := 0;
  if v_qid is not null then
    for r in
      select c.qid, c.title, c.linked, c.median_views, c.category
      from ripples.candidates c
      where c.as_of = p_as_of and c.root_qid = v_qid and c.depth = 1 and coalesce(c.linked, true)
        and coalesce(c.median_views, 0) >= 300 and c.qid <> v_qid
        and not exists (select 1 from ripples.blocklist b where b.qid = c.qid)
        and not exists (select 1 from ripples.articles a where a.qid = c.qid and (a.is_disambig or a.is_list or a.blocked))
      order by coalesce(c.cs_rank, 999), coalesce(c.set_rank, 999), c.median_views desc nulls last
    loop
      exit when k >= coalesce((caps ->> 'P-WIKI')::int, 15);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.qid,
              jsonb_build_array(jsonb_build_object('type','WIKI','from',v_qid,'to',r.qid,'sign',0,'s',1.0,'source','Wikipedia outlink','title',r.title)),
              'P-WIKI', 0, null, v_onset, k, 0.7, 0);
      k := k + 1; n := n + 1;
    end loop;
  end if;

  -- P-COM: co-mention pairs (GKG / TV / sitemaps) with PMI z ≥ 2, only when the source has κ ≥ 0.3; the proposing channel is excluded
  k := 0;
  for r in
    select ed.source, t.qid, ed.pmi, ed.n, (ed.pmi - st.mu) / nullif(st.sd, 0) pmi_z, ripples.att_series_channel(s0.series_id) ch
    from ripples.att_edges ed
    join ripples.att_topics t on t.topic_id = ed.to_topic and t.qid is not null
    join (select source, avg(pmi) mu, stddev_samp(pmi) sd from ripples.att_edges where period between p_as_of - 90 and p_as_of and pmi is not null group by source) st on st.source = ed.source
    left join lateral (select series_id from ripples.att_series s where s.source = ed.source limit 1) s0 on true
    where ed.from_topic = v_topic and ed.period between p_as_of - 90 and p_as_of and ed.pmi is not null
      and ripples.att_source_kappa(ed.source) >= 0.3
    order by (ed.pmi - st.mu) / nullif(st.sd, 0) desc nulls last
  loop
    exit when k >= coalesce((caps ->> 'P-COM')::int, 10);
    if r.pmi_z is null or r.pmi_z < 2 then exit; end if;
    insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, excluded_ch, rank_in_path, aware, jumps)
    values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.qid,
            jsonb_build_array(jsonb_build_object('type','GK','from',v_from,'to',r.qid,'sign',0,'s',least(1, r.pmi_z / 5.0),'source','co-coverage ' || r.source,'pmi_z',round(r.pmi_z::numeric,2))),
            'P-COM', 0, null, v_onset, array[r.ch], k, least(1, r.pmi_z / 5.0), 0);
    k := k + 1; n := n + 1;
  end loop;
  return n;
end $$;

-- Freeze (att_freeze_candidates): see 25_att_engine_ledger.sql, per-batch version.

-- Canonical frozen payload of a freeze batch (rows ordered by hop_id; immutable columns only). A batch is one freeze call: the whole
-- live day, or one library event with its decoys. p_unfrozen selects the rows being frozen now (optionally limited to p_events);
-- p_hash selects the rows of an existing batch, so every ledger freeze row recomputes bit-identically from att_hop_candidates.
drop function if exists ripples.att_freeze_payload(date, boolean);
drop function if exists ripples.att_freeze_hash(date, boolean);
create or replace function ripples.att_freeze_payload(p_as_of date, p_unfrozen boolean default false, p_hash text default null, p_events bigint[] default null) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('as_of', p_as_of, 'method', coalesce(ripples._att_cfg('engine') ->> 'method', '6.0'),
    'hops', coalesce((select jsonb_agg(jsonb_build_array(c.hop_id, c.event_id, c.role, c.parent_hop, c.depth, c.path, c.path_type, c.node,
                                                        c.prior::float8, c.bh_weight::float8, c.channels, c.excluded_ch, c.window_close, c.looks, c.sign, c.onset)
                                       order by c.hop_id)
                      from ripples.att_hop_candidates c where c.as_of = p_as_of
                        and (case when p_unfrozen then c.frozen_hash is null and (p_events is null or c.event_id = any(p_events))
                                  when p_hash is not null then c.frozen_hash = p_hash
                                  else c.frozen_hash is not null end)),
                     '[]'::jsonb))
$$;

create or replace function ripples.att_freeze_hash(p_as_of date, p_unfrozen boolean default false, p_hash text default null, p_events bigint[] default null) returns text
language sql stable set search_path = '' as $$
  select encode(extensions.digest(ripples._canon(ripples.att_freeze_payload(p_as_of, p_unfrozen, p_hash, p_events))::text, 'sha256'), 'hex')
$$;

-- att_freeze_candidates(p_as_of, p_library, p_events): defined in 25_att_engine_ledger.sql (per-batch version).

-- Base rate p̂ = P(Likely+ | family, path type, channel) from resolved registry rows (≥ 20), else the frozen prior
create or replace function ripples.att_base_rate(p_hop bigint) returns real
language sql stable set search_path = '' as $$
  select coalesce(
    (select (sum(hit::int)::float8 / count(*))::real from ripples.att_hop_registry r
      where r.resolved_at is not null and r.family = ev.family and r.path_type = c.path_type and r.channel = coalesce(c.channels[1], 'none')
      having count(*) >= 20),
    c.prior)
  from ripples.att_hop_candidates c join ripples.att_events ev on ev.event_id = c.event_id where c.hop_id = p_hop
$$;

-- Verify the ledger chain and every freeze batch against a recomputation from att_hop_candidates (ENGINE §12.4).
-- A freeze row superseded by a later re-freeze (ref.superseded_by, see att_refreeze) is skipped; the superseding row is verified instead.
create or replace function ripples.att_ledger_verify() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare l record; prev text; bad jsonb := '[]'::jsonb; cnt int := 0; v_day date; recomputed text; n_snap int := 0; n_freeze int := 0; snap jsonb;
begin
  prev := coalesce((select v ->> 'prev_hash' from ripples.att_state where k = 'engine.ledger.genesis'), repeat('0', 64));
  for l in select * from ripples.att_ledger order by seq loop
    cnt := cnt + 1;
    if l.prev_hash <> prev or l.chain_hash <> encode(extensions.digest(l.prev_hash || l.payload_hash, 'sha256'), 'hex') then
      bad := bad || jsonb_build_object('seq', l.seq, 'why', 'chain');
    end if;
    if l.kind = 'freeze' and not (l.ref ? 'superseded_by') then
      n_freeze := n_freeze + 1;
      v_day := (l.ref ->> 'as_of')::date;
      recomputed := ripples.att_freeze_hash(v_day, false, l.payload_hash);
      if recomputed <> l.payload_hash then
        bad := bad || jsonb_build_object('seq', l.seq, 'why', 'freeze_recompute', 'day', v_day);
      end if;
      select payload into snap from ripples.att_freeze_snapshots where payload_hash = l.payload_hash;
      if snap is not null then
        n_snap := n_snap + 1;
        if encode(extensions.digest(ripples._canon(snap)::text, 'sha256'), 'hex') <> l.payload_hash then
          bad := bad || jsonb_build_object('seq', l.seq, 'why', 'snapshot_hash');
        end if;
      end if;
    end if;
    prev := l.chain_hash;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(bad) = 0, 'rows', cnt, 'head', ripples.att_ledger_head(), 'bad', bad,
                            'freeze_batches', n_freeze, 'freeze_snapshots', n_snap,
                            'unproven_batches', (select count(*) from ripples.att_ledger where kind = 'freeze' and ref ? 'refreeze_of'),
                            'unproven_hops', (select count(*) from ripples.att_hop_candidates where not freeze_proven),
                            'tests_without_candidate', (select count(*) from ripples.att_hop_tests t where not exists (select 1 from ripples.att_hop_candidates c where c.hop_id = t.hop_id and c.frozen_hash is not null)),
                            'candidates_without_freeze_row', (select count(*) from ripples.att_hop_candidates c where c.frozen_hash is not null
                                                              and not exists (select 1 from ripples.att_ledger g where g.kind = 'freeze' and g.payload_hash = c.frozen_hash)));
end $$;

do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'ripples' and c.relkind = 'r' and c.relname like 'att\_%' loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on table ripples.%I from anon, authenticated, public', t);
  end loop;
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
