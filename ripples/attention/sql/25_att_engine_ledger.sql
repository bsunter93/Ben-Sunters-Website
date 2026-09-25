-- Migration: att_engine_ledger (WS-B, Ripple Map v6, 2026-09-25)
-- Model-version ledger row (seed priors + template versions + prior_cutoff hashed, ENGINE §2.1 / §5.7 / §10.6), library / backfill mode
-- (att_library_event, att_run_library, att_run_day; reconstructed = true, excluded from live denominators and the prior set), the
-- negative-control pool fix in att_freeze_candidates, decoy target resolution for shifted-self decoys, the wider topic-placebo pool,
-- engine retention and the cron rows (att-zvec 05:50, att-pick-events 07:31, att-freeze 07:34, att-tick existing, att-finalize 08:20,
-- att-expand 08:45, att-calibrate Sunday 09:10). Depends on 20–24.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Model version (hash of the seed prior table, mechanism template versions, prior_cutoff and the engine config)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_model_version_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare payload jsonb; h text; v_seq bigint; existing bigint;
begin
  payload := jsonb_build_object(
    'method', coalesce(ripples._att_cfg('engine') ->> 'method', '6.0'),
    'prior_cutoff', ripples._att_cfg('engine') ->> 'prior_cutoff',
    'engine_config', ripples._att_cfg('engine'),
    'seed_priors', (select jsonb_agg(jsonb_build_array(etype, channel, family, prior::float8, version) order by etype, channel, family, version) from ripples.att_edge_priors where seeded),
    'templates', (select coalesce(jsonb_agg(jsonb_build_array(template, family, version, sign, channel, l_days) order by template), '[]'::jsonb) from ripples.att_mech_templates),
    'channel_stat', (select jsonb_agg(jsonb_build_array(channel, kind, stat_kind, l_days, sided, min_kappa_measured::float8) order by channel) from ripples.att_channel_stat),
    'families', (select jsonb_agg(jsonb_build_array(family, scheduled, mapper) order by family) from ripples.att_families));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  select seq into existing from ripples.att_ledger where kind = 'model_version' and payload_hash = h limit 1;
  if existing is not null then return jsonb_build_object('seq', existing, 'hash', h, 'new', false); end if;
  v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('method', payload ->> 'method', 'prior_cutoff', payload ->> 'prior_cutoff'), payload);
  return jsonb_build_object('seq', v_seq, 'hash', h, 'new', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Candidate generation: decoys resolve mapper targets through their matched real event (same candidate generation by construction)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_gen_candidates(p_event bigint, p_as_of date, p_parent_hop bigint default null, p_depth int default 1,
                                                       p_from_node text default null, p_onset date default null) returns int
language plpgsql security definer set search_path = '' as $$
declare e record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); caps jsonb; v_from text; v_topic bigint; v_onset date;
        v_qid text; it jsonb; nd text; n int := 0; r record; v_family text; k int; v_tgt bigint; v_map_from text;
begin
  select * into e from ripples.att_events where event_id = p_event;
  if not found then return 0; end if;
  caps := coalesce(cfg -> 'caps', '{}'::jsonb);
  v_from := coalesce(p_from_node, e.qid);
  v_onset := coalesce(p_onset, e.onset);
  v_family := e.family;
  v_topic := case when v_from ~ '^Q[0-9]+$' then (select topic_id from ripples.att_topics where qid = v_from) when v_from is not null then ripples.att_node_topic(v_from) end;
  if v_topic is null then v_topic := e.topic_id; end if;
  if v_topic is null then return 0; end if;
  v_qid := case when v_from ~ '^Q[0-9]+$' then v_from end;
  -- target resolution (topic keys / meta) goes through the matched real event for decoys: identical candidate generation (ENGINE §1.3).
  -- MAP edges too: a decoy tests the matched real's mapped targets at the decoy's (calm) onset, so every P-MAP cell has decoy coverage.
  v_tgt := coalesce(case when e.role = 'decoy' and e.matched_to is not null then (select topic_id from ripples.att_events where event_id = e.matched_to) end, e.topic_id);
  v_map_from := coalesce(case when e.role = 'decoy' and e.matched_to is not null and p_depth = 1 then (select qid from ripples.att_events where event_id = e.matched_to) end, v_from);

  -- The family mapper and the mechanism library are event-level: they only apply at depth 1. Deeper hops follow edges from the
  -- parent node (MAP / WD / WIKI / co-coverage), never the event's own target list again.
  k := 0;
  for it in select x from ripples.att_families f, jsonb_array_elements(f.mapper) x where f.family = v_family and p_depth = 1 loop
    for nd in select * from ripples.att_resolve_targets(it, v_tgt) loop
      exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(v_from, 'event:' || p_event),'to',nd,'sign',coalesce((it->>'sign')::int,0),'s',1.0,'template',it->>'template','source','family mapper')),
              'P-MAP', coalesce((it->>'sign')::int, 0), null, v_onset, it->>'template', k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;
  for r in select m.to_node, m.sign, m.strength, m.template, m.meta from ripples.att_mech_edges m
            where m.etype = 'MAP' and m.valid_to is null and m.from_node in (coalesce(v_map_from, ''), 'family:' || v_family) order by m.strength desc, m.edge_id loop
    exit when k >= coalesce((caps ->> 'P-MAP')::int, 25);
    insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
    values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, r.to_node,
            jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(v_from, 'event:' || p_event),'to',r.to_node,'sign',r.sign,'s',r.strength,'template',r.template,'source','map edge','meta',r.meta)
                              || case when v_map_from is distinct from v_from then jsonb_build_object('via_matched', v_map_from) else '{}'::jsonb end),
            'P-MAP', r.sign, null, v_onset, r.template, k, 0, 1);
    k := k + 1; n := n + 1;
  end loop;

  k := 0;
  for r in select t.* from ripples.att_mech_templates t where t.family = v_family and p_depth = 1 order by t.template loop
    for nd in select * from ripples.att_resolve_targets(r.target_pattern, v_tgt) loop
      exit when k >= coalesce((caps ->> 'P-MECH')::int, 10);
      insert into ripples.att_cand_stage(as_of, event_id, role, parent_hop, depth, u_topic, node, path, path_type, sign, prior, onset, template, rank_in_path, aware, jumps)
      values (p_as_of, p_event, e.role, p_parent_hop, p_depth, v_topic, nd,
              jsonb_build_array(jsonb_build_object('type','MECH','from',coalesce(v_from, 'event:' || p_event),'to',nd,'sign',r.sign,'s',1.0,'template',r.template,'source','mechanism library v' || r.version,'text',r.rationale)),
              'P-MECH', r.sign, null, v_onset, r.template, k, 0, 1);
      k := k + 1; n := n + 1;
    end loop;
  end loop;

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
            jsonb_build_array(jsonb_build_object('type','GK','from',coalesce(v_from, 'event:' || p_event),'to',r.qid,'sign',0,'s',least(1, r.pmi_z / 5.0),'source','co-coverage ' || r.source,'pmi_z',round(r.pmi_z::numeric,2))),
            'P-COM', 0, null, v_onset, array[r.ch], k, least(1, r.pmi_z / 5.0), 0);
    k := k + 1; n := n + 1;
  end loop;
  -- never re-propose a node this event already tests (any depth) nor the parent node itself (no self-loops)
  if p_depth > 1 then
    delete from ripples.att_cand_stage s
     where s.as_of = p_as_of and s.event_id = p_event and s.parent_hop is not distinct from p_parent_hop and s.depth = p_depth
       and (s.node = v_from or exists (select 1 from ripples.att_hop_candidates c where c.event_id = p_event and c.node = s.node));
    get diagnostics k = row_count; n := n - k;
  end if;
  return n;
end $$;

-- Negative-control pool: every outcome node with κ ≥ 0.5 across the store (not only nodes already in bundles)
create or replace function ripples.att_negative_pool(p_event bigint, p_as_of date, p_n int default 3) returns setof text
language sql stable security definer set search_path = '' as $$
  select node from (
    select distinct s.source || ':' || s.key node
    from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id
    join ripples.att_engine_source_map m on m.source = s.source join ripples.att_channel_stat cs on cs.channel = m.channel
    where cs.kind = 'outcome' and m.channel <> 'MONEY' and z.kappa >= 0.5 and s.key <> '__total__'
      and s.source || ':' || s.key not in (select node from ripples.att_cand_stage where as_of = p_as_of and event_id = p_event)) x
  order by encode(extensions.digest(p_event::text || ':' || node, 'sha256'), 'hex') limit p_n
$$;

-- Freeze one batch: the whole live day (p_events null) or, in library mode, one event with its decoys (p_events). Every batch has its
-- own frozen_hash and ledger 'freeze' row, so a batch recomputes bit-identically whatever else is frozen on the same as_of day.
drop function if exists ripples.att_freeze_candidates(date, boolean);
create or replace function ripples.att_freeze_candidates(p_as_of date, p_library boolean default false, p_events bigint[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; r record; cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); n_stage int := 0; n_ins int := 0; n_new_nodes int := 0;
        v_hash text; v_seq bigint; m int; v_mean float8; v_events int := 0; ch text; v_chs text[]; v_avail text[]; v_l int; v_looks date[];
        v_close date; v_prior float8; v_pi_min float8 := coalesce((cfg->>'pi_min')::float8, 0.05); v_hardcap int := coalesce((cfg->>'hard_cap_tests')::int, 1600);
        v_tchan text; v_h float8; n_neg int := 0; v_frozen_before int; pe jsonb; scope bigint[];
begin
  -- scope: the events this batch freezes (never one that already has frozen rows)
  if p_events is null then
    select count(*) into v_frozen_before from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is not null and reconstructed = p_library;
    if v_frozen_before > 0 then
      return jsonb_build_object('as_of', p_as_of, 'already_frozen', v_frozen_before,
                                'frozen_hash', (select frozen_hash from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is not null and reconstructed = p_library limit 1));
    end if;
    select coalesce(array_agg(event_id), '{}') into scope from ripples.att_events
     where as_of = p_as_of and role in ('real','decoy','library','positive_control') and coalesce(reconstructed, false) = p_library;
  else
    -- an event may be frozen on several days (depth-1 on its own day, depth-2 children the next morning): one batch per (event, day)
    select coalesce(array_agg(ev.event_id), '{}') into scope from ripples.att_events ev
     where ev.event_id = any(p_events) and coalesce(ev.reconstructed, false) = p_library
       and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = ev.event_id and c.as_of = p_as_of and c.frozen_hash is not null);
    if cardinality(scope) = 0 then return jsonb_build_object('as_of', p_as_of, 'already_frozen', true, 'events', 0); end if;
  end if;
  delete from ripples.att_cand_stage where as_of = p_as_of and depth = 1 and role <> 'fork_check' and event_id = any(scope);

  for e in select * from ripples.att_events where event_id = any(scope) and as_of = p_as_of order by event_id loop   -- depth-1 on the event's own day
    v_events := v_events + 1;
    n_stage := n_stage + ripples.att_gen_candidates(e.event_id, p_as_of);
  end loop;
  select n_stage + count(*) into n_stage from ripples.att_cand_stage where as_of = p_as_of and (depth >= 2 or role = 'fork_check') and event_id = any(scope);

  for e in select * from ripples.att_events where event_id = any(scope) and as_of = p_as_of and role in ('real','library','positive_control') loop
    for r in select * from ripples.att_negative_pool(e.event_id, p_as_of, 3) as t(node) loop
      insert into ripples.att_cand_stage(as_of, event_id, role, depth, u_topic, node, path, path_type, sign, onset, rank_in_path, aware, jumps)
      values (p_as_of, e.event_id, 'negative_control', 1, coalesce(e.topic_id, ripples.att_node_topic(r.node)), r.node,
              jsonb_build_array(jsonb_build_object('type','MAP','from',coalesce(e.qid, 'event:' || e.event_id),'to',r.node,'sign',0,'s',1.0,'source','negative control')), 'P-NEG', 0, e.onset, n_neg, 0, 1);
      n_neg := n_neg + 1;
    end loop;
  end loop;

  delete from ripples.att_cand_stage s using (
    select ctid, row_number() over (partition by as_of, event_id, parent_hop, node, path_type, role order by rank_in_path) rn
    from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope)) d
  where s.ctid = d.ctid and d.rn > 1;

  for r in select distinct node from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope) loop
    if ripples.att_node_topic(r.node) is null then
      if r.node ~ '^Q[0-9]+$' and n_new_nodes < 60 then
        perform ripples.att_register_topic(r.node, coalesce((select p->>'title' from ripples.att_cand_stage s, jsonb_array_elements(s.path) p
                                                              where s.node = r.node and s.as_of = p_as_of and p ? 'title' limit 1), r.node),
                                            'hop', null, null, 'active', 'en', null, false, '{}'::jsonb);
        n_new_nodes := n_new_nodes + 1;
      elsif r.node ~ '^Q[0-9]+$' then
        insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
        values (r.node, 'unslotted:' || r.node, r.node, 'en', 'dormant', false, 'hop', jsonb_build_object('unslotted', p_as_of))
        on conflict do nothing;
      else
        delete from ripples.att_cand_stage where as_of = p_as_of and node = r.node and event_id = any(scope);
        continue;
      end if;
    end if;
    perform ripples.att_node_bundle(r.node);
  end loop;

  for r in select s.* from ripples.att_cand_stage s where s.as_of = p_as_of and s.event_id = any(scope) order by s.event_id, s.depth, s.path_type, s.rank_in_path loop
    if ripples.att_node_topic(r.node) is null then continue; end if;
    select array_agg(distinct ns.channel order by ns.channel) into v_chs
      from ripples.att_node_series ns where ns.node = r.node and not (ns.channel = any(r.excluded_ch));
    v_chs := coalesce(v_chs, '{}');
    select array_agg(distinct ns.channel) into v_avail
      from ripples.att_node_series ns join ripples.att_zvec z on z.series_id = ns.series_id
      where ns.node = r.node and z.kappa >= 0.3 and not (ns.channel = any(r.excluded_ch));
    select ns.channel into v_tchan from ripples.att_node_series ns join ripples.att_channel_stat cs on cs.channel = ns.channel
      where ns.node = r.node and not (ns.channel = any(r.excluded_ch)) order by (cs.kind = 'outcome') desc, ns.channel limit 1;
    v_tchan := coalesce(v_tchan, v_chs[1], 'READ');
    v_prior := 1;
    for pe in select p from jsonb_array_elements(r.path) p loop
      v_prior := v_prior * ripples.att_edge_prior(pe ->> 'type', v_tchan, (select family from ripples.att_events where event_id = r.event_id))
                         * coalesce((pe ->> 's')::float8, 1);
    end loop;
    if r.role = 'negative_control' then v_prior := ripples.att_edge_prior('MAP', v_tchan, 'any'); end if;
    v_looks := '{}'; v_l := 0;
    foreach ch in array v_chs loop
      v_l := greatest(v_l, ripples.att_l_days(ch));
      v_looks := v_looks || ripples.att_look_dates(ch, r.onset, ripples.att_l_days(ch));
    end loop;
    if cardinality(v_chs) = 0 then v_l := 7; v_looks := array[r.onset + 8]; end if;
    select array_agg(distinct d order by d) into v_looks from unnest(v_looks) d;
    v_close := r.onset + v_l;
    v_h := (1 - r.aware) * (0.5 + 0.5 * least(1, r.jumps));
    insert into ripples.att_hop_candidates(as_of, u_topic, v_topic, proposed_by, edge, status, event_id, role, parent_hop, depth, path, path_type,
                                           prior, channels, excluded_ch, window_close, looks, voi, node, onset, sign, reconstructed)
    values (p_as_of, r.u_topic, ripples.att_node_topic(r.node), array[r.path_type], r.path -> 0,
            case when cardinality(coalesce(v_avail, '{}')) = 0 then 'waiting_series' else 'queued' end,
            r.event_id, r.role, r.parent_hop, r.depth, r.path, r.path_type, v_prior::real, v_chs, r.excluded_ch, v_close, v_looks,
            (v_prior * (1 - v_prior) * (0.5 + 0.5 * v_h))::real, r.node, r.onset, r.sign, p_library);
    n_ins := n_ins + 1;
  end loop;
  delete from ripples.att_cand_stage where as_of = p_as_of and event_id = any(scope);

  delete from ripples.att_hop_candidates c using (
    select hop_id, row_number() over (partition by as_of, event_id, parent_hop, node order by prior desc, hop_id) rn
    from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope)) d
  where c.hop_id = d.hop_id and d.rn > 3;
  delete from ripples.att_hop_candidates c using (
    select hop_id, row_number() over (partition by as_of, event_id order by (role = 'negative_control') desc, voi desc, hop_id) rn
    from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope)) d
  where c.hop_id = d.hop_id and d.rn > coalesce((cfg -> 'caps' ->> 'event')::int, 60) + 3;
  select count(*) into m from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  if m > v_hardcap then
    delete from ripples.att_hop_candidates c using (
      select hop_id, row_number() over (order by (path_type in ('P-WIKI','P-COM')) desc, voi asc, hop_id desc) rn
      from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope) and role <> 'negative_control') d
    where c.hop_id = d.hop_id and d.rn <= m - v_hardcap;
  end if;
  update ripples.att_hop_candidates set status = 'skipped' where as_of = p_as_of and frozen_hash is null and event_id = any(scope) and prior < v_pi_min and role <> 'negative_control';

  -- BH weights, frozen before data are read: w = clamp(π / mean π, 0.2, 5), renormalised to Σ w = m over the batch
  select count(*), avg(prior) into m, v_mean from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  if m = 0 then return jsonb_build_object('as_of', p_as_of, 'events', v_events, 'frozen', 0); end if;
  update ripples.att_hop_candidates set bh_weight = least(5, greatest(0.2, prior / nullif(v_mean, 0))) where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  update ripples.att_hop_candidates c set bh_weight = (c.bh_weight * m / s.tot)::real
    from (select sum(bh_weight) tot from ripples.att_hop_candidates where as_of = p_as_of and frozen_hash is null and event_id = any(scope)) s
   where c.as_of = p_as_of and c.frozen_hash is null and c.event_id = any(scope);

  v_hash := ripples.att_freeze_hash(p_as_of, true, null, scope);
  v_seq := ripples.att_ledger_append(p_as_of, 'freeze', jsonb_build_object('as_of', p_as_of, 'm', m, 'events', v_events, 'library', p_library, 'event_ids', to_jsonb(scope)),
                                     ripples.att_freeze_payload(p_as_of, true, null, scope));
  update ripples.att_hop_candidates set frozen_hash = v_hash, frozen_at = now() where as_of = p_as_of and frozen_hash is null and event_id = any(scope);
  for e in select distinct c.event_id from ripples.att_hop_candidates c where c.as_of = p_as_of and c.frozen_hash = v_hash order by 1 loop
    v_seq := ripples.att_ledger_append(p_as_of, 'register', jsonb_build_object('event_id', e.event_id),
      (select coalesce(jsonb_agg(jsonb_build_object('hop_id', c.hop_id, 'window_close', c.window_close, 'p_hat', ripples.att_base_rate(c.hop_id)) order by c.hop_id), '[]'::jsonb)
         from ripples.att_hop_candidates c where c.as_of = p_as_of and c.event_id = e.event_id and c.frozen_hash = v_hash));
    insert into ripples.att_hop_registry(hop_id, window_close, p_hat, family, path_type, channel, ledger_seq)
    select c.hop_id, c.window_close, ripples.att_base_rate(c.hop_id), ev.family, c.path_type, coalesce(c.channels[1], 'none'), v_seq
    from ripples.att_hop_candidates c join ripples.att_events ev on ev.event_id = c.event_id
    where c.as_of = p_as_of and c.event_id = e.event_id and c.frozen_hash = v_hash
    on conflict (hop_id) do nothing;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'events', v_events, 'staged', n_stage, 'frozen', m, 'negative_controls', n_neg,
                            'new_nodes', n_new_nodes, 'frozen_hash', v_hash, 'ledger_seq', v_seq);
end $$;

-- Repair: re-freeze a batch whose rows changed after its freeze (only ever needed after the pre-rollback harness deleted fixture rows
-- out of shared day batches on 2026-09-25). Appends a superseding 'freeze' row and marks the old row superseded; nothing is deleted.
create or replace function ripples.att_refreeze(p_old_hash text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_day date; v_old bigint; v_new text; v_seq bigint; m int;
begin
  select seq, (ref ->> 'as_of')::date into v_old, v_day from ripples.att_ledger where kind = 'freeze' and payload_hash = p_old_hash;
  if v_old is null then return jsonb_build_object('error', 'no such freeze row'); end if;
  select count(*) into m from ripples.att_hop_candidates where frozen_hash = p_old_hash;
  if m = 0 then return jsonb_build_object('error', 'no rows carry that hash'); end if;
  v_new := ripples.att_freeze_hash(v_day, false, p_old_hash);
  if v_new = p_old_hash then return jsonb_build_object('ok', true, 'note', 'batch already recomputes'); end if;
  v_seq := ripples.att_ledger_append(v_day, 'freeze', jsonb_build_object('as_of', v_day, 'm', m, 'refreeze_of', v_old, 'reason', p_reason),
                                     ripples.att_freeze_payload(v_day, false, p_old_hash));
  update ripples.att_hop_candidates set frozen_hash = v_new where frozen_hash = p_old_hash;
  update ripples.att_ledger set ref = ref || jsonb_build_object('superseded_by', v_seq) where seq = v_old;
  return jsonb_build_object('ok', true, 'day', v_day, 'old_seq', v_old, 'new_seq', v_seq, 'rows', m);
end $$;

-- Topic family (ENGINE §5.1): same source and kind, same baseline decile, coverage Jaccard ≥ 0.8; when the source holds fewer than 30
-- eligible series the pool widens to the same channel and value kind across sources (conservative: still "anything of this type").
-- Draws are ordered by decile distance first (the own decile, then the neighbouring ones), so a thin decile still yields ≥ 30 draws.
create or replace function ripples.att_topic_draws(p_hop bigint, p_max int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c record; s record; pool bigint[]; draws jsonb := '[]'::jsonb; i int; n_min int := null; bundle jsonb; ps jsonb := '{}'::jsonb; k text; n_src int;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  for s in select ns.series_id, ns.channel, se.source, se.metric, z.base_level, z.n_obs_90, z.value_kind
           from ripples.att_node_series ns join ripples.att_series se on se.series_id = ns.series_id join ripples.att_zvec z on z.series_id = ns.series_id
           where ns.node = c.node and z.kappa >= 0.3 and z.grain = 'day' and not (ns.channel = any(coalesce(c.excluded_ch, '{}'))) loop
    select count(*) into n_src from ripples.att_zvec z join ripples.att_series se on se.series_id = z.series_id
      where se.source = s.source and se.metric = s.metric and se.key <> '__total__' and z.kappa >= 0.3 and z.grain = 'day';
    with cand as (
      select z.series_id, z.base_level, z.n_obs_90, ntile(10) over (order by z.base_level) dec
      from ripples.att_zvec z join ripples.att_series se on se.series_id = z.series_id
      where se.key <> '__total__' and z.kappa >= 0.3 and z.grain = 'day'
        and case when n_src >= 30 then se.source = s.source and se.metric = s.metric
                 else ripples.att_series_channel(z.series_id) = s.channel and z.value_kind = s.value_kind end),
    me as (select dec from cand where series_id = s.series_id)
    select coalesce(array_agg(cand.series_id order by abs(cand.dec - me.dec), encode(extensions.digest(cand.series_id::text || p_hop::text, 'sha256'), 'hex')), '{}') into pool
    from cand, me
    where cand.series_id <> s.series_id
      and least(cand.n_obs_90, s.n_obs_90)::float8 / greatest(cand.n_obs_90, s.n_obs_90, 1) >= 0.8
      and cand.series_id not in (select ns2.series_id from ripples.att_node_series ns2 where ns2.node = c.node)
      -- series that are themselves frozen targets of the same event (any path) are hypothesised responders, not a null reference
      and cand.series_id not in (select ns3.series_id from ripples.att_node_series ns3 join ripples.att_hop_candidates c3 on c3.node = ns3.node where c3.event_id = c.event_id);
    ps := ps || jsonb_build_object(s.series_id::text, jsonb_build_object('channel', s.channel, 'pool', to_jsonb(pool)));
    n_min := least(coalesce(n_min, cardinality(pool)), cardinality(pool));
  end loop;
  if n_min is null or n_min = 0 then return '[]'::jsonb; end if;
  for i in 1..least(n_min, p_max) loop
    bundle := '[]'::jsonb;
    for k in select * from jsonb_object_keys(ps) loop
      bundle := bundle || jsonb_build_object('series_id', (ps -> k -> 'pool' ->> (i - 1))::bigint, 'channel', ps -> k ->> 'channel');
    end loop;
    draws := draws || jsonb_build_array(bundle);
  end loop;
  return draws;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Library / backfill mode (ENGINE §5.8; WS-E drives it). reconstructed = true everywhere; excluded from live denominators.
-- ---------------------------------------------------------------------------------------------------------------------
-- Register a reconstructed event (+ 8 family-matched decoys: same mappers, onsets shifted 6–45 weeks earlier, "shifted-self" decoys,
-- because a calm-page match cannot be verified without attention data that far back). Returns the event_id.
create or replace function ripples.att_library_event(p_qid text, p_label text, p_family text, p_onset date, p_role text default 'library') returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_topic bigint; v_id bigint; k int; v_slug text; d_topic bigint; d_onset date; kk int;
begin
  if p_qid is not null then
    select topic_id into v_topic from ripples.att_topics where qid = p_qid;
    if v_topic is null then
      v_topic := ripples.att_register_topic(p_qid, p_label, 'cascade', null, null, 'panel', 'en', p_label, false, jsonb_build_object('family', p_family));
    end if;
  else
    insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
    values (null, 'library:' || ripples.att_slugify(p_label) || ':' || p_onset, p_label, 'en', 'panel', false, 'cascade', jsonb_build_object('family', p_family, 'library', true))
    on conflict (label_key) do nothing;
    select topic_id into v_topic from ripples.att_topics where label_key = 'library:' || ripples.att_slugify(p_label) || ':' || p_onset;
  end if;
  select event_id into v_id from ripples.att_events where reconstructed and role = p_role and onset = p_onset and (qid = p_qid or label = p_label);
  if v_id is not null then return v_id; end if;
  v_slug := ripples.att_slugify(p_label) || '-' || to_char(p_onset, 'YYYY');
  if exists (select 1 from ripples.att_events where slug = v_slug) then v_slug := v_slug || '-' || to_char(p_onset, 'MM-DD'); end if;
  insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug, reconstructed)
  values (p_onset, v_topic, p_qid, p_label, p_family, p_role, p_onset, null, false, v_slug, true) returning event_id into v_id;
  perform ripples.att_library_decoys(v_id);
  return v_id;
end $$;

-- Shifted-self decoys for a reconstructed event that has none yet (WS-E's library collectors create events without them): 8 onsets
-- 6–45 weeks earlier, same family and mappers. They are frozen with the real's day when that day is still unfrozen, else on the first
-- unfrozen day after it (one freeze batch per day keeps att_freeze_hash(day) bit-identical).
create or replace function ripples.att_library_decoys(p_event bigint) returns int
language plpgsql security definer set search_path = '' as $$
declare ev record; k int; kk int; d_onset date; d_topic bigint; n int := 0; v_as_of date;
begin
  select * into ev from ripples.att_events where event_id = p_event and reconstructed;
  if not found then return 0; end if;
  if (select count(*) from ripples.att_events d where d.matched_to = p_event and d.role = 'decoy') >= 8 then return 0; end if;
  v_as_of := ev.as_of;
  if exists (select 1 from ripples.att_hop_candidates c where c.as_of = v_as_of and c.frozen_hash is not null) then
    -- the real's day is already frozen (without these decoys): use the first unfrozen day after it
    v_as_of := ev.as_of + 1;
    while exists (select 1 from ripples.att_hop_candidates c where c.as_of = v_as_of and c.frozen_hash is not null) loop v_as_of := v_as_of + 1; end loop;
  end if;
  for k in 1..8 loop
    if exists (select 1 from ripples.att_topics where label_key = 'decoy:' || p_event || ':' || k) then continue; end if;
    kk := 6 + (abs(hashtext(p_event::text || ':' || k)) % 40);
    d_onset := ev.onset - 7 * kk;
    insert into ripples.att_topics(qid, label_key, label, lang, status, in_panel, origin, meta)
    values (null, 'decoy:' || p_event || ':' || k, ev.label || ' (shifted-self decoy ' || k || ')', 'en', 'panel', false, 'cascade',
            jsonb_build_object('shifted_self', ev.qid, 'decoy_of', p_event))
    on conflict (label_key) do nothing;
    select topic_id into d_topic from ripples.att_topics where label_key = 'decoy:' || p_event || ':' || k;
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, matched_to, slug, reconstructed)
    values (v_as_of, d_topic, null, ev.label || ' (shifted-self decoy ' || k || ')', ev.family, 'decoy', d_onset, null, false, p_event, null, true)
    on conflict do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Run one reconstructed event end to end: decoys → freeze (every as_of day of the event and its decoys) → every pre-registered look →
-- finalize → expand → depth-2 round
create or replace function ripples.att_run_library(p_event bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev record; fr jsonb; d date; fin jsonb; last_look date; ex jsonb; fr2 jsonb; fin2 jsonb; last2 date; n_ran int := 0; r jsonb; a date; n_dec int; e2 record;
begin
  select * into ev from ripples.att_events where event_id = p_event and reconstructed;
  if not found then return jsonb_build_object('error', 'not a reconstructed event'); end if;
  -- an event registered after its day was frozen (library collectors add events with past as_of) is processed on the next unfrozen day
  if exists (select 1 from ripples.att_hop_candidates c where c.as_of = ev.as_of and c.frozen_hash is not null)
     and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = p_event) then
    a := ev.as_of + 1;
    while exists (select 1 from ripples.att_hop_candidates c where c.as_of = a and c.frozen_hash is not null) loop a := a + 1; end loop;
    update ripples.att_events set as_of = a where event_id = p_event;
    ev.as_of := a;
  end if;
  -- decoys for every library event sharing this day (the freeze is per day, so they must exist before it)
  n_dec := 0;
  for e2 in select event_id from ripples.att_events where reconstructed and role in ('library','positive_control') and as_of = ev.as_of loop
    n_dec := n_dec + ripples.att_library_decoys(e2.event_id);
  end loop;
  for a in select distinct e.as_of from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event order by 1 loop
    fr := ripples.att_freeze_candidates(a, true, (select array_agg(e.event_id) from ripples.att_events e where (e.event_id = p_event or e.matched_to = p_event) and e.as_of = a));
  end loop;
  for d in select distinct l from ripples.att_hop_candidates c join ripples.att_events e on e.event_id = c.event_id, unnest(c.looks) l
           where c.reconstructed and (e.event_id = p_event or e.matched_to = p_event) and l <= current_date order by 1 loop
    r := ripples.att_engine_run_due(d, 100000, true);
    n_ran := n_ran + (r ->> 'ran')::int;
    last_look := d;
  end loop;
  fin := case when last_look is not null then ripples.att_finalize(last_look, true) end;
  if last_look is not null then perform ripples.att_chain_decide(last_look); end if;
  ex := ripples.att_expand(coalesce(last_look, ev.as_of), true);
  if (ex ->> 'children')::int > 0 then
    fr2 := ripples.att_freeze_candidates(coalesce(last_look, ev.as_of) + 1, true, (select array_agg(e.event_id) from ripples.att_events e where e.event_id = p_event or e.matched_to = p_event));
    for d in select distinct l from ripples.att_hop_candidates c, unnest(c.looks) l where c.as_of = coalesce(last_look, ev.as_of) + 1 and c.reconstructed and l <= current_date order by 1 loop
      r := ripples.att_engine_run_due(d, 100000, true);
      n_ran := n_ran + (r ->> 'ran')::int;
      last2 := d;
    end loop;
    fin2 := case when last2 is not null then ripples.att_finalize(last2, true) end;
    if last2 is not null then perform ripples.att_chain_decide(last2); end if;
  end if;
  perform ripples.att_build_cascade(p_event, coalesce(last2, last_look, ev.as_of));
  return jsonb_build_object('event_id', p_event, 'decoys_created', n_dec, 'freeze', fr - 'frozen_hash', 'looks_ran', n_ran, 'final_day', last_look, 'finalize', fin, 'expand', ex,
                            'depth2', fr2 - 'frozen_hash', 'finalize2', fin2);
end $$;

-- Daily driver for backfills. 'live': the whole pipeline synchronously for one day; 'library': every reconstructed event picked that day.
create or replace function ripples.att_run_day(p_as_of date, p_mode text default 'live') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; out jsonb := '[]'::jsonb; pk jsonb; fr jsonb; ran jsonb; fin jsonb; ex jsonb;
begin
  if p_mode = 'library' then
    for e in select event_id from ripples.att_events where reconstructed and role in ('library','positive_control') and as_of = p_as_of order by event_id loop
      out := out || ripples.att_run_library(e.event_id);
    end loop;
    return jsonb_build_object('as_of', p_as_of, 'mode', 'library', 'events', out);
  end if;
  pk := ripples.att_pick_events(p_as_of);
  fr := ripples.att_freeze_candidates(p_as_of, false);
  ran := ripples.att_engine_run_due(p_as_of, 100000, false);
  fin := ripples.att_finalize(p_as_of, false);
  perform ripples.att_chain_decide(p_as_of);
  ex := ripples.att_expand(p_as_of, false);
  return jsonb_build_object('as_of', p_as_of, 'mode', 'live', 'pick', pk, 'freeze', fr - 'frozen_hash', 'ran', ran, 'finalize', fin, 'expand', ex);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Retention (engine tables; ENGINE §9 storage budget) and the pick fallback when today's seeds are not in yet
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_engine_retention() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a int; b int; c int; d int; e int;
begin
  delete from ripples.att_placebo_draws where hop_id in (select hop_id from ripples.att_hop_candidates where as_of < current_date - 7) or hop_id is null; get diagnostics a = row_count;
  delete from ripples.att_placebo_top where created_at < now() - interval '7 days'; get diagnostics e = row_count;
  delete from ripples.att_sd_null where as_of < current_date - 30; get diagnostics b = row_count;
  delete from ripples.att_cand_stage where as_of < current_date - 3; get diagnostics c = row_count;
  delete from ripples.att_fluke_bins where as_of < current_date - 400; get diagnostics d = row_count;
  return jsonb_build_object('placebo_rows', a, 'placebo_top', e, 'sd_null', b, 'stage', c, 'fluke_bins', d,
                            'db_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
                            'zvec_mb', round(pg_total_relation_size('ripples.att_zvec') / 1048576.0, 1));
end $$;

-- att_retention: created only if no other workstream has defined it; delegates to the engine retention
do $$ begin
  if to_regprocedure('ripples.att_retention()') is null then
    create function ripples.att_retention() returns jsonb language sql security definer set search_path = '' as 'select ripples.att_engine_retention()';
    revoke all on function ripples.att_retention() from anon, authenticated, public;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Library backfill stepper (WS-E's archive and the 30-day decoy backfill run through it; one event per call, advisory-locked,
--    never inside the 07:25–08:25 morning window). State in att_state 'engine.library'.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_library_step(p_from date default null, p_to date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jsonb := coalesce(ripples.att_state_get('engine.library'), '{}'::jsonb); ev record; r jsonb; t0 timestamptz := clock_timestamp();
        v_from date := coalesce(p_from, (st ->> 'from')::date, current_date - 60); v_to date := coalesce(p_to, (st ->> 'to')::date, current_date - 1);
begin
  if (now() at time zone 'utc')::time between '07:25' and '08:25' then return jsonb_build_object('skipped', 'morning window'); end if;
  select e.* into ev from ripples.att_events e
   where e.reconstructed and e.role in ('library','positive_control') and e.onset between v_from and v_to
     and (not exists (select 1 from ripples.att_hop_candidates c where c.event_id = e.event_id)
          or (select count(*) from ripples.att_events d where d.matched_to = e.event_id and d.role = 'decoy') < 8
          or exists (select 1 from ripples.att_events d where d.matched_to = e.event_id and d.role = 'decoy'
                     and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = d.event_id)))
     and coalesce((st -> 'failed_at' ->> e.event_id::text)::timestamptz, '1970-01-01'::timestamptz) < now() - interval '2 hours'   -- a failed event is retried after 2 h
   order by e.onset desc, e.event_id limit 1;
  if not found then
    perform ripples.att_state_set('engine.library', st || jsonb_build_object('from', v_from, 'to', v_to, 'idle_at', now()));
    return jsonb_build_object('idle', true, 'from', v_from, 'to', v_to);
  end if;
  begin
    r := ripples.att_run_library(ev.event_id);
  exception when others then
    st := coalesce(ripples.att_state_get('engine.library'), '{}'::jsonb);   -- re-read: the run may have been long
    st := st || jsonb_build_object('failed_at', coalesce(st -> 'failed_at', '{}'::jsonb) || jsonb_build_object(ev.event_id::text, now()),
                                   'last_error', jsonb_build_object('event_id', ev.event_id, 'error', left(sqlerrm, 300), 'at', now()));
    perform ripples.att_state_set('engine.library', st || jsonb_build_object('from', v_from, 'to', v_to));
    return jsonb_build_object('event_id', ev.event_id, 'error', left(sqlerrm, 300));
  end;
  st := coalesce(ripples.att_state_get('engine.library'), '{}'::jsonb) - 'failed' - 'last_error';
  st := st || jsonb_build_object('failed_at', coalesce(st -> 'failed_at', '{}'::jsonb) - ev.event_id::text);
  st := st || jsonb_build_object('from', v_from, 'to', v_to, 'last', jsonb_build_object('event_id', ev.event_id, 'label', ev.label, 'onset', ev.onset,
                                 'looks_ran', r -> 'looks_ran', 'finalize', r -> 'finalize', 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1), 'at', now()),
                                 'done', coalesce((st ->> 'done')::int, 0) + 1);
  perform ripples.att_state_set('engine.library', st);
  return jsonb_build_object('event_id', ev.event_id, 'label', ev.label, 'onset', ev.onset, 'looks_ran', r -> 'looks_ran', 'finalize', r -> 'finalize',
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

create or replace function ripples.att_library_step_locked(p_from date default null, p_to date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not pg_try_advisory_lock(hashtext('ripples.att_library_step')) then return jsonb_build_object('skipped', 'another stepper holds the lock'); end if;
  begin
    r := ripples.att_library_step(p_from, p_to);
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
  return r;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Live pick: seeds for the day may land under yesterday's as_of (the v5 ripples-tick writes them 06:00–08:59)
-- ---------------------------------------------------------------------------------------------------------------------
drop function if exists ripples.att_pick_events(date);
create or replace function ripples.att_pick_events(p_as_of date, p_seed_day date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s record; v_topic bigint; v_family text; v_sens boolean; v_id bigint; n_real int := 0; n_decoy int := 0; n_sched int := 0; n_cont int := 0;
        v_slug text; v_match bigint; v_disc text; c record; v_seed date := coalesce(p_seed_day, p_as_of);
begin
  for s in select * from ripples.seeds where as_of = v_seed and role = 'real' order by rank loop
    select topic_id into v_topic from ripples.att_topics where qid = s.qid;
    if v_topic is null then
      v_topic := ripples.att_register_topic(s.qid, s.title, 'cascade', null, null, 'active', 'en', s.title, false, '{}'::jsonb);
    end if;
    if exists (select 1 from ripples.att_events e where e.qid = s.qid and e.onset = s.onset and e.role = 'real' and not e.reconstructed) then
      n_cont := n_cont + 1; continue;
    end if;
    v_disc := (select x from unnest(s.sources) x where x not like 'topcountry:%' and x not like 'wikitop:%' and x not like 'featured:%' limit 1);
    v_family := ripples.att_family_of(v_topic, s.onset, v_disc);
    select coalesce(a.sensitive, false) into v_sens from ripples.articles a where a.qid = s.qid;
    v_slug := ripples.att_slugify(s.title) || '-' || to_char(s.onset, 'YYYY');
    if exists (select 1 from ripples.att_events e where e.slug = v_slug) then v_slug := v_slug || '-' || to_char(s.onset, 'MM-DD'); end if;
    if exists (select 1 from ripples.att_events e where e.slug = v_slug) then v_slug := v_slug || '-' || lower(s.qid); end if;
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug)
    values (p_as_of, v_topic, s.qid, s.title, v_family, 'real', s.onset,
            case when s.peak_multiple > 0 then ln(s.peak_multiple) end, coalesce(v_sens, false), v_slug)
    on conflict (as_of, topic_id, role) do update set onset = excluded.onset, magnitude = excluded.magnitude, family = excluded.family
    returning event_id into v_id;
    n_real := n_real + 1;
  end loop;
  for s in select * from ripples.seeds where as_of = v_seed and role = 'decoy' order by rank loop
    select topic_id into v_topic from ripples.att_topics where qid = s.qid;
    if v_topic is null then
      v_topic := ripples.att_register_topic(s.qid, s.title, 'cascade', null, null, 'panel', 'en', s.title, false, '{}'::jsonb);
    end if;
    if exists (select 1 from ripples.att_events e where e.qid = s.qid and e.onset = s.onset and e.role = 'decoy' and not e.reconstructed) then
      n_cont := n_cont + 1; continue;
    end if;
    select e.event_id, e.family into v_match, v_family from ripples.att_events e
     where e.role = 'real' and e.qid = s.matched_to and not e.reconstructed order by e.as_of desc limit 1;
    if v_family is null then v_family := ripples.att_family_of(v_topic, s.onset, null); end if;
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, matched_to, slug)
    values (p_as_of, v_topic, s.qid, s.title, v_family, 'decoy', s.onset, null, false, v_match, null)
    on conflict (as_of, topic_id, role) do update set onset = excluded.onset, family = excluded.family, matched_to = excluded.matched_to;
    n_decoy := n_decoy + 1;
  end loop;
  for c in select * from ripples.att_family_calendar where scheduled_for between p_as_of - 1 and p_as_of loop
    v_topic := null;
    if c.qid is not null then select topic_id into v_topic from ripples.att_topics where qid = c.qid; end if;
    if exists (select 1 from ripples.att_events e where e.role = 'real' and e.family = c.family and e.onset = c.scheduled_for
               and (e.qid = c.qid or e.label = c.label)) then continue; end if;
    v_slug := ripples.att_slugify(c.label) || '-' || to_char(c.scheduled_for, 'YYYY-MM-DD');
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug)
    values (p_as_of, v_topic, c.qid, c.label, c.family, 'real', c.scheduled_for, null, false,
            case when exists (select 1 from ripples.att_events where slug = v_slug) then v_slug || '-' || c.id else v_slug end)
    on conflict do nothing;
    n_sched := n_sched + 1;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'seed_day', v_seed, 'real', n_real, 'decoy', n_decoy, 'scheduled', n_sched, 'continuing', n_cont);
end $$;

create or replace function ripples.att_pick_events_cron(p_day date default current_date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d date;
begin
  select max(as_of) into d from ripples.seeds where as_of between p_day - 2 and p_day;
  if d is null then return jsonb_build_object('as_of', p_day, 'note', 'no seeds'); end if;
  return ripples.att_pick_events(p_day, d);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Cron (UTC). pg_cron sessions inherit the 2-minute statement_timeout, so the long engine steps raise it explicitly.
--    att-zvec-a/b/c 05:50–07:20 · att-pick-events 07:31 · att-freeze 07:34 · att-engine-tick 07:35–08:18 (≤ 40 looks/min) ·
--    att-finalize-engine 08:20 · att-expand 08:45 · att-calibrate-engine Sunday 09:10 · att-engine-retention 09:40 ·
--    att-library-run every 2 min outside the morning window (WS-E archive + decoy backfill).
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare j record; begin
  for j in select jobid, jobname from cron.job where jobname in ('att-zvec','att-zvec-once','att-test-once','att-zvec-a','att-zvec-b','att-zvec-c','att-pick-events','att-freeze',
                                                                 'att-engine-tick-a','att-engine-tick-b','att-finalize-engine','att-expand','att-calibrate-engine','att-engine-retention','att-library-run') loop
    perform cron.unschedule(j.jobid);
  end loop;
end $$;
select cron.schedule('att-zvec-a', '50-59 5 * * *', $$set statement_timeout = '110s'; select ripples.att_zvec_step_locked(current_date - 1, 75)$$);
select cron.schedule('att-zvec-b', '* 6 * * *',     $$set statement_timeout = '110s'; select ripples.att_zvec_step_locked(current_date - 1, 75)$$);
select cron.schedule('att-zvec-c', '0-20 7 * * *',  $$set statement_timeout = '110s'; select ripples.att_zvec_step_locked(current_date - 1, 75)$$);
select cron.schedule('att-pick-events', '31 7 * * *', $$select ripples.att_pick_events_cron(current_date)$$);
select cron.schedule('att-freeze', '34 7 * * *', $$set statement_timeout = '20min'; select ripples.att_pick_events_cron(current_date); select ripples.att_freeze_candidates(current_date)$$);
select cron.schedule('att-engine-tick-a', '35-59 7 * * *', $$set statement_timeout = '110s'; select ripples.att_engine_tick_locked(current_date, 40, 50)$$);
select cron.schedule('att-engine-tick-b', '0-18 8 * * *',  $$set statement_timeout = '110s'; select ripples.att_engine_tick_locked(current_date, 40, 50)$$);
select cron.schedule('att-finalize-engine', '20 8 * * *', $$set statement_timeout = '25min'; select ripples.att_finalize(current_date); select ripples.att_chain_decide(current_date)$$);
select cron.schedule('att-expand', '45 8 * * *', $$set statement_timeout = '10min'; select ripples.att_expand(current_date)$$);
select cron.schedule('att-calibrate-engine', '10 9 * * 0', $$set statement_timeout = '50min'; select ripples.att_calibrate(current_date - 1)$$);
select cron.schedule('att-engine-retention', '40 9 * * *', $$select ripples.att_engine_retention()$$);
select cron.schedule('att-library-run', '*/2 * * * *', $$set statement_timeout = '30min'; select ripples.att_library_step_locked()$$);

select ripples.att_model_version_register();

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
