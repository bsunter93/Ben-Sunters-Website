-- 07_rm_pond_integration.sql — Ripple Map integration (2026-09-26): real engine + story-layer output as static public JSON.
-- Source of record for migrations rm_integration_p1_route_ideas_public, rm_integration_p2_pond, rm_integration_p3_stories_control,
-- rm_integration_p4_contract_grants (Supabase kffkasnzqcddpystszch). Additive; tiers are never written here.
--
--   * route ideas: the engine's IO route ideas carried raw node ids ("family:hazard.heat → hiringlab.postings:sales"), so the leak
--     guard held every library line. rm_route_ideas_public() rebuilds them with public names and drops any without one.
--   * ripples.rm_pond_payload(event)  : the pond page's data shape (ripples/pond/data/milton.json, tools/snapshot.mjs) built from the
--     latest PUBLIC frozen version of the line + the engine tables. Public lines only; tiers are the published (gated) tiers.
--   * ripples.rm_pond_index()         : the list of pond payloads (flagship first).
--   * public.rm_pond(p_slug)          : anon RPC — index when p_slug is null, else one payload; null when not public or leaking.
--   * ripples.rm_story_public_control : a positive control is returned by rm_stories only when listed in att_config
--     story.public_controls AND it has a public line (today: 213 Hurricane Milton, the owner's flagship). It stays is_control = true.
--   * ripples.rm_pond_contract_test() : fixture shape (rm_contract_fixtures 'pond.json'), leak guard, tier honesty.
--   * rm_grant_audit(): allowlists public.rm_pond.

-- ---------------------------------------------------------------- p1: route ideas
insert into ripples.rm_node_names(node, label, basis)
select n, 'US job postings: ' || replace(split_part(n, ':', 2), '_', ' '), 'Indeed Hiring Lab job postings index, category ' || split_part(n, ':', 2)
  from (select distinct to_node n from ripples.att_mech_edges where to_node like 'hiringlab.postings:%'
        union select distinct from_node from ripples.att_mech_edges where from_node like 'hiringlab.postings:%') x
on conflict (node) do nothing;

create or replace function ripples.rm_route_ideas_public(p jsonb, p_event bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  with ev as (select e.event_id, e.label, e.qid, e.family from ripples.att_events e where e.event_id = p_event),
  items as (select x, o from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality a(x, o)),
  m as (
    select i.o, i.x,
           (select jsonb_build_object('from', me.from_node, 'to', me.to_node) from ripples.att_mech_edges me, ev
             where me.etype = 'IO' and me.from_node in (ev.qid, 'family:' || ev.family)
               and ripples.att_node_label(me.from_node) || ' → ' || ripples.att_node_label(me.to_node) || ' (input-output link)' = i.x ->> 'text'
             order by me.to_node limit 1) e
      from items i),
  pub as (
    select m.o, m.x, case when m.e ->> 'from' like 'family:%' then (select ev.label from ev) else ripples.rm_label_resolve(m.e ->> 'from', null) end f,
           ripples.rm_label_resolve(m.e ->> 'to', null) t
      from m where m.e is not null)
  select coalesce(jsonb_agg(jsonb_build_object('text', pub.f || ' → ' || pub.t || ' (input-output link)',
                                               'source', coalesce(pub.x ->> 'source', 'BEA 2017 IO table'),
                                               'status', coalesce(pub.x ->> 'status', 'hypothesis, not measured')) order by pub.o), '[]'::jsonb)
    from pub where pub.f is not null and pub.t is not null
$$;
revoke all on function ripples.rm_route_ideas_public(jsonb, bigint) from public, anon, authenticated;
-- rm_cascade_content (live definition, anchor-replaced like tools/bq/att_ce_publish_gate.sql):
--   'route_ideas', coalesce(ws -> 'route_ideas', '[]'::jsonb),   →   'route_ideas', ripples.rm_route_ideas_public(ws -> 'route_ideas', ev.event_id),

-- ---------------------------------------------------------------- p2: pond payload
-- pattern outcome domains (6.2 domain_outcome) onto the pond's public domains; 'business' is the pond's own far-shore domain
create or replace function ripples.rm_pond_domain(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'power' then 'real_world' when 'travel' then 'real_world' when 'weather' then 'real_world'
                when 'labor' then 'jobs' when 'government' then 'institutions' when 'developer' then 'builders'
                when 'business' then 'business' else coalesce(ripples.rm_domain8(p), 'reading') end
$$;

create or replace function ripples.rm_pond_payload(p_event bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare ev ripples.att_events; pv record; pl jsonb; eff jsonb := '[]'; flats jsonb := '[]'; unt jsonb := '[]'; ctl jsonb := '[]'; shore jsonb := '[]';
        n jsonb; t record; g jsonb; reg record; cand record; st record; fx jsonb; ch jsonb; rep jsonb; keys text[]; dom_order text[] :=
        array['real_world','institutions','jobs','markets','business','builders','stuff','reading','chatter'];
        used text[] := '{}'; out jsonb; story jsonb; travel jsonb; honesty jsonb; watching jsonb; nm text; lab text; name text; sid bigint;
        pat jsonb; pnext jsonb; hero_hop bigint; n_meas_eng int := 0; n_meas int := 0; n_like int := 0; n_chain int := 0; quiet boolean; mag float8;
        wd int; unit text; rho float8; reg_seqs bigint[] := '{}';
begin
  select * into ev from ripples.att_events where event_id = p_event;
  if not found or not ripples.rm_is_public(p_event) or coalesce(ripples.att_story_off_limits(p_event), false) then return null; end if;
  select v.version, v.payload, v.published_at into pv from ripples.rm_public_versions v where v.event_id = p_event order by v.version desc limit 1;
  pl := pv.payload;
  lab := pl -> 'event' ->> 'label';
  name := regexp_replace(lab, '\s*\(positive control\)$', '');
  quiet := coalesce((pl -> 'event' ->> 'sensitive')::boolean, ripples.rm_sensitive(p_event));
  select s.* into st from ripples.att_story_candidates s where s.event_id = p_event and s.story_kind = 'cascade' and s.exclude_reason is null
   order by s.featurable desc, s.story_score desc, s.story_id limit 1;
  hero_hop := st.hero_stop;

  -- effects: every Likely-or-better stop of the published version (tier = the published, gated tier)
  for n in select x from jsonb_array_elements(coalesce(pl -> 'nodes', '[]')) x where x ->> 'tier' in ('measured','likely')
           order by (x ->> 'tier' = 'measured') desc, ((x ->> 'hop_id')::bigint = hero_hop) desc, (x ->> 'hop_id')::bigint loop
    select * into t from ripples.att_hop_latest l where l.hop_id = (n ->> 'hop_id')::bigint;
    select * into reg from ripples.att_hop_registry r where r.hop_id = (n ->> 'hop_id')::bigint;
    select * into cand from ripples.att_hop_candidates c where c.hop_id = (n ->> 'hop_id')::bigint;
    g := ripples.att_ce_gate((n ->> 'hop_id')::bigint, coalesce(t.tier, n ->> 'tier'));
    if t.tier = 'measured' then n_meas_eng := n_meas_eng + 1; end if;
    if reg.ledger_seq is not null then reg_seqs := reg_seqs || reg.ledger_seq; end if;
    if n ->> 'tier' = 'measured' then n_meas := n_meas + 1; else n_like := n_like + 1; end if;
    if coalesce((n ->> 'depth')::int, 1) > 1 then n_chain := n_chain + 1; end if;
    unit := coalesce(n ->> 'unit', 'x'); rho := (n ->> 'rho')::float8;
    mag := case when rho is null then null when unit = 'x' and rho > 0 then least(1, abs(ln(rho)) / 0.25) else least(1, abs(rho) / 1.0) end;
    used := used || coalesce(n ->> 'domain', 'reading');
    -- regional contrast (engine 6.2) on the same series family, when the storm has one covering this node
    select jsonb_build_object(
             'pass', f.p_space <= 0.05 and f.p_pre >= 0.10 and sign(f.d) = gr.expected_sign and (not gr.synth or sign(coalesce(f.synth_d, f.d)) = sign(f.d)),
             'strong', f.p_space <= 0.05 and f.p_pre >= 0.10 and sign(f.d) = gr.expected_sign and (not gr.synth or sign(coalesce(f.synth_d, f.d)) = sign(f.d))
                       and f.p_time <= 0.05 and abs(f.z) >= 3,
             'design', 'affected vs unaffected regions (difference-in-differences), in-space and in-time placebos' || case when gr.synth then ', synthetic control' else '' end,
             'd_logpts', round(f.d::numeric, 4), 'effect_pct', round(((exp(f.d) - 1) * 100)::numeric, 1), 'z', round(f.z::numeric, 2), 'se', round(f.se::numeric, 4),
             'p_space', round(f.p_space::numeric, 4), 'p_space_odds', case when f.p_space > 0 then round(1 / f.p_space) end, 'p_time', round(f.p_time::numeric, 4),
             'p_pre', round(f.p_pre::numeric, 3), 'leads', (select jsonb_agg(round(x::numeric, 4)) from unnest(f.lead) x),
             'synth_d', round(f.synth_d::numeric, 4), 'synth_p', round(f.synth_p::numeric, 3), 'synth_ratio', round(f.synth_ratio::numeric, 2),
             'n_donors', f.n_donors, 'treated', to_jsonb(f.treated),
             'window', jsonb_build_object('pre_days', gr.pre_n, 'post_days', gr.post_n, 'lag_days', gr.lag_n, 'grain', case when gr.pre_n <= 8 then 'week' else 'day' end, 'onset', f.onset),
             'in_time', jsonb_build_object('n', (select count(*) from unnest(f.placebo_d) x where x is not null),
                                           'n_bigger', (select count(*) from unnest(f.placebo_d) x where x is not null and abs(x - f.med) >= abs(f.d - f.med)),
                                           'values_logpts', (select jsonb_agg(round(x::numeric, 4)) from unnest(f.placebo_d) x where x is not null), 'centre', round(f.med::numeric, 4)),
             'computed_at', f.computed_at, 'grid', jsonb_build_object('grid_id', gr.grid_id, 'batch', gr.batch, 'expected_sign', gr.expected_sign, 'frozen_hash', gr.frozen_hash, 'ledger_seq', gr.ledger_seq),
             'replication', (select jsonb_build_object(
                 'n_similar', count(*) filter (where f2.d is not null),
                 'n_seen', count(*) filter (where f2.p_space <= 0.05 and f2.p_pre >= 0.10 and sign(f2.d) = gr.expected_sign),
                 'n_same_direction', count(*) filter (where sign(f2.d) = gr.expected_sign),
                 'rule', 'seen = the pre-registered regional contrast passed (in-space p <= 0.05, pre-trends flat, expected sign)',
                 'examples', coalesce(jsonb_agg(jsonb_build_object('label', e2.label, 'onset', e2.onset, 'effect_pct', round(((exp(f2.d) - 1) * 100)::numeric, 1), 'z', round(f2.z::numeric, 2), 'quiet', ripples.rm_sensitive(e2.event_id))
                                                order by f2.z * gr.expected_sign desc)
                                      filter (where f2.p_space <= 0.05 and f2.p_pre >= 0.10 and sign(f2.d) = gr.expected_sign and not coalesce(ripples.att_story_off_limits(e2.event_id), false)), '[]'),
                 'family', (select jsonb_build_object('effect_pct', fe.pct, 'ci_pct', jsonb_build_array(fe.pct_lo, fe.pct_hi), 'p_placebo', round(fe.p_placebo::numeric, 4), 'q', round(fe.q::numeric, 4),
                                                      'strength', fe.strength, 'n_events', fe.n_events, 'i2', round(fe.i2::numeric, 2))
                              from ripples.att_family_effects fe where fe.grid_id = gr.grid_id order by fe.computed_at desc limit 1))
               from ripples.att_fx_event f2 join ripples.att_events e2 on e2.event_id = f2.event_id where f2.grid_id = gr.grid_id and f2.role = 'real' and f2.event_id <> p_event))
      into fx
      from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id
     where f.event_id = p_event and f.role in ('real','live') and gr.source = split_part(n ->> 'node', ':', 1)
       and substr(n ->> 'node', strpos(n ->> 'node', ':') + 1) = any (f.treated) and f.d is not null
     order by f.p_space nulls last limit 1;
    -- the daily series behind the chart: the hop's own series, indexed to its 28-day pre-window mean
    select s.series_id into sid from ripples.rm_hop_series((n ->> 'hop_id')::bigint) s limit 1;
    ch := null;
    if sid is not null then
      with pre as (select avg(o.value) m from ripples.attention_obs o where o.series_id = sid and o.day between ev.onset - 28 and ev.onset - 1),
           d as (select o.day, o.value from ripples.attention_obs o where o.series_id = sid
                    and o.day between ev.onset - 28 and least(coalesce((n ->> 'window_close')::date, ev.onset + 21) + 14, ev.onset + 90))
      select jsonb_build_object('kind', 'series', 'grain', 'day', 'onset', ev.onset, 'observed_onset', n -> 'onset',
               'series', coalesce(jsonb_agg(jsonb_build_object('d', d.day, 't', round((d.value / nullif(pre.m, 0))::numeric, 4), 'o', null, 'v', round(d.value::numeric, 2)) order by d.day), '[]'),
               'band', case when jsonb_typeof(n -> 'band') = 'object' then jsonb_build_object('lo', n -> 'band' -> 'lo' -> 0, 'hi', n -> 'band' -> 'hi' -> 0,
                                  'note', 'the engine''s own normal band for this series (±1.28σ)') end,
               'pre_window', jsonb_build_array(ev.onset - 28, ev.onset - 1), 'post_window', jsonb_build_array(coalesce(n ->> 'onset', ev.onset::text), n -> 'window_close'),
               'peak', (select jsonb_build_object('d', d2.day, 't', round((d2.value / nullif(pre.m, 0))::numeric, 4)) from d d2
                         where d2.day >= ev.onset order by case when rho < 1 then d2.value else -d2.value end limit 1))
        into ch from d, pre group by pre.m;
    end if;
    rep := (select s.replication from ripples.att_story_candidates s where s.event_id = p_event and s.hero_stop = (n ->> 'hop_id')::bigint and s.story_kind = 'cascade' limit 1);
    eff := eff || jsonb_build_object(
      'id', 'h' || (n ->> 'hop_id'), 'hop_id', (n ->> 'hop_id')::bigint, 'node', n ->> 'node', 'domain_key', coalesce(n ->> 'domain', 'reading'),
      'lag_days', n -> 'lag_days', 'lag_text', ripples.rm_lag_phrase((n ->> 'lag_days')::float8), 'onset_observed', n -> 'onset', 'magnitude', round(mag::numeric, 4),
      'tier', n ->> 'tier', 'engine_tier', coalesce(t.tier, n ->> 'tier'),
      'published', jsonb_build_object('tier', n ->> 'tier', 'engine_tier', coalesce(t.tier, n ->> 'tier'), 'reason', g ->> 'reason', 'mode', g ->> 'mode', 'ce', g -> 'ce',
                                      'text', case when g ->> 'reason' is not null then initcap(coalesce(t.tier, '')) || ' by the engine; ' || (g ->> 'reason')
                                                   else initcap(n ->> 'tier') end),
      'tier_reason', n -> 'tier_reason',
      'engine', jsonb_build_object('version', coalesce(t.detail ->> 'engine_version', pl ->> 'method'), 't_stat', round(t.t_stat::numeric, 3), 'p_date', t.p_date, 'n_date', t.n_date,
                                   'exceed_date', case when t.p_date is not null and t.n_date is not null then round(t.p_date * t.n_date) end,
                                   'p_topic', t.p_topic, 'n_topic', t.n_topic, 'p_link', t.p_link, 'n_link', t.n_link, 'q', t.q, 'q_w', t.q_w, 'fluke', t.fluke,
                                   'f', t.f, 'f_bin', t.f_bin, 'f_warming', n -> 'f_warming',
                                   'rho', jsonb_build_object('shrunk', t.rho_shrunk, 'lo', t.rho_lo, 'hi', t.rho_hi, 'raw', t.rho_raw, 'unit', unit),
                                   'channels', n -> 'channels', 'common_shock', t.common_shock, 'reversed', t.reversed, 'lag_ok', t.lag_ok, 'flags', to_jsonb(t.flags),
                                   'look_day', t.look_day, 'resolved_at', reg.resolved_at, 'chain', t.detail -> 'chain'),
      'contrast', fx, 'kind', 'pad', 'far_shore', false,
      'parent', case when n ->> 'parent_hop' is null then 'event' else 'h' || (n ->> 'parent_hop') end,
      'mediation_supported', (n ->> 'parent_hop') is not null and coalesce((st.fields ->> 'mediation_supported')::boolean, false) and st.hero_stop = (n ->> 'hop_id')::bigint, 'common_cause', '[]'::jsonb,
      'num', case when rho is null then null when unit = 'x' then to_char(rho, 'FM990.00') || '×' else to_char(rho, 'SG990.00') || ' pts' end,
      'short', n ->> 'label', 'title', n ->> 'label', 'unit', case when unit = 'x' then 'its normal' else 'points vs its normal' end,
      'headline', case when st.hero_stop = (n ->> 'hop_id')::bigint then st.copy ->> 'story_sentence' else split_part(n ->> 'sentence', '. ', 1) || '.' end,
      'plain', n ->> 'sentence',
      'sources', jsonb_build_object('agree', n -> 'channels' -> 'agree', 'of', n -> 'channels' -> 'of',
                                    'text', coalesce(n -> 'channels' ->> 'agree', '0') || ' of ' || coalesce(n -> 'channels' ->> 'of', '0') || ' independent channels agree'),
      'mechanism', coalesce((select jsonb_agg(jsonb_build_object('step', p ->> 'text', 'why', null, 'source', coalesce(p ->> 'source', 'mechanism library'))) from jsonb_array_elements(coalesce(n -> 'path', '[]')) p), '[]'),
      'fluke', case when t.n_date is not null then jsonb_build_object('n', t.n_date, 'hits', round(t.p_date * t.n_date),
                    'text', 'About 1 in ' || coalesce(n ->> 'p_1_in', '?') || ' random pairings look this strong.') end,
      'replication', coalesce(fx -> 'replication', rep),
      'story_replication', rep,
      'chart', ch,
      'ledger', jsonb_build_object('register_seq', reg.ledger_seq, 'test_seq', t.ledger_seq, 'version_seq', pl -> 'ledger' -> 'seq', 'frozen_hash', cand.frozen_hash),
      'label_side', 'auto');
  end loop;

  -- flats: pre-registered stops whose window closed with no move (the published version's `flat`), with their own test
  for n in select x from jsonb_array_elements(coalesce(pl -> 'flat', '[]')) x order by (x ->> 'hop_id')::bigint loop
    select * into t from ripples.att_hop_latest l where l.hop_id = (n ->> 'hop_id')::bigint;
    select * into cand from ripples.att_hop_candidates c where c.hop_id = (n ->> 'hop_id')::bigint;
    select * into reg from ripples.att_hop_registry r where r.hop_id = (n ->> 'hop_id')::bigint;
    used := used || coalesce(n ->> 'domain', 'reading');
    flats := flats || jsonb_build_object('id', 'h' || (n ->> 'hop_id'), 'hop_id', (n ->> 'hop_id')::bigint, 'node', n ->> 'node', 'name', n ->> 'label',
      'domain_key', coalesce(n ->> 'domain', 'reading'), 'lag_days', cand.window_close - ev.onset, 'window_close', cand.window_close, 'prior', round(reg.p_hat::numeric, 3),
      'tier', 'flat', 'rho', n -> 'rho', 't_stat', round(t.t_stat::numeric, 2), 'p_date', t.p_date, 'n_date', t.n_date, 'q_w', t.q_w, 'flags', to_jsonb(t.flags),
      'mechanism', cand.path -> 0 ->> 'text', 'path_type', cand.path_type,
      'plain', (n ->> 'label') || ' stayed inside its normal range for the window we pre-registered (to ' || to_char(cand.window_close, 'FMDD Mon YYYY') || '; prior '
               || coalesce(round(reg.p_hat * 100)::text || '%', 'not set') || ')' ||
               case when t.p_date is not null and t.n_date is not null then '. ' || round(t.p_date * t.n_date) || ' of ' || t.n_date || ' fake dates did as well or better.' else '.' end);
  end loop;

  -- untested / watching: stops the engine has no verdict on yet (window open, or waiting for data)
  for n in select x from jsonb_array_elements(coalesce(pl -> 'nodes', '[]')) x where x ->> 'tier' = 'watching' or coalesce((x ->> 'provisional')::boolean, false)
           order by (x ->> 'window_close') nulls last, (x ->> 'hop_id')::bigint loop
    select * into cand from ripples.att_hop_candidates c where c.hop_id = (n ->> 'hop_id')::bigint;
    used := used || coalesce(n ->> 'domain', 'reading');
    unt := unt || jsonb_build_object('id', 'h' || (n ->> 'hop_id'), 'hop_id', (n ->> 'hop_id')::bigint, 'node', n ->> 'node', 'name', n ->> 'label',
      'domain_key', coalesce(n ->> 'domain', 'reading'), 'lag_days', (n ->> 'window_close')::date - ev.onset, 'window_close', n -> 'window_close',
      'window_closed', n -> 'window_closed', 'due', n -> 'due', 'prior', n -> 'p_hat', 'status', n -> 'tier_reason', 'cascade_word', 'watching',
      'mechanism', n -> 'path' -> 0 ->> 'text', 'path_type', cand.path_type, 'plain', n ->> 'sentence');
  end loop;

  -- negative controls (pre-registered series the storm should NOT move); only those with a public name
  select coalesce(jsonb_agg(jsonb_build_object('hop_id', c.hop_id, 'name', ripples.rm_label_resolve(c.node, null), 'tier', l.tier, 't_stat', round(l.t_stat::numeric, 2),
                                               'p_date', l.p_date, 'n_date', l.n_date, 'window_close', c.window_close) order by c.hop_id), '[]')
    into ctl
    from ripples.att_hop_candidates c left join ripples.att_hop_latest l on l.hop_id = c.hop_id
   where c.event_id = p_event and c.path_type = 'P-NEG' and ripples.rm_label_resolve(c.node, null) is not null and not ripples.rm_node_hidden(c.node);

  -- far shore: 6.2 world rules for this event family (a rule about events like it, never evidence about this one)
  for pat in select x from jsonb_array_elements(coalesce(public.rm_patterns(ev.family, 'pattern'), '[]')) x
             where not coalesce((x ->> 'is_check')::boolean, false) and not coalesce((x ->> 'definitional')::boolean, false)
             order by (x ->> 'q')::float8, (x ->> 'id')::int limit 3 loop
    wd := coalesce((pat -> 'window' ->> 'post')::int, 1) * case when pat -> 'window' ->> 'grain' = 'week' then 7 else 1 end;
    select ripples.rm_pond_domain(fe.domain_outcome) into nm from ripples.att_family_effects fe where fe.grid_id = (pat ->> 'id')::int order by fe.computed_at desc limit 1;
    nm := coalesce(nm, 'business'); used := used || nm;
    shore := shore || jsonb_build_object('id', 'pattern-' || (pat ->> 'id'), 'kind', 'pattern', 'domain_key', nm, 'lag_days', wd, 'far_shore', true, 'tier', 'pattern',
      'strength', pat ->> 'strength', 'num', case when (pat ->> 'effect')::float8 < 0 then '−' else '+' end || to_char(abs((pat ->> 'effect')::float8), 'FM990.0') || '%',
      'short', pat ->> 'outcome_label', 'title', pat ->> 'outcome_label', 'unit', 'across ' || (pat ->> 'n_events') || ' past events',
      'headline', pat ->> 'headline',
      'plain', coalesce((select sc.copy ->> 'story_sentence' from ripples.att_story_candidates sc where sc.story_id = 'pattern:' || (pat ->> 'id')), (pat ->> 'headline') || '.') || ' This is a rule about events like this one, not evidence about this one'
               || case when exists (select 1 from ripples.att_fx_event f where f.event_id = p_event and f.grid_id = (pat ->> 'id')::int and f.d is not null)
                       then '.' else ': this event was not tested on it.' end,
      'pattern', pat, 'story', (select jsonb_build_object('story_id', sc.story_id, 'archetype', sc.archetype, 'story_sentence', sc.copy ->> 'story_sentence')
                                  from ripples.att_story_candidates sc where sc.story_id = 'pattern:' || (pat ->> 'id')));
  end loop;
  select x into pnext from jsonb_array_elements(coalesce(public.rm_patterns(null, 'strong pattern'), '[]')) x
   where x ->> 'family' is distinct from ev.family order by (x ->> 'q')::float8, (x ->> 'id')::int limit 1;

  -- domains actually drawn, in canonical order; every item carries its index into `domains`
  keys := array(select d from unnest(dom_order) d where d = any (used));
  if cardinality(keys) = 0 then keys := array['real_world']; end if;
  eff := (select coalesce(jsonb_agg(x || jsonb_build_object('domain', array_position(keys, x ->> 'domain_key') - 1) order by o), '[]') from jsonb_array_elements(eff) with ordinality a(x, o));
  flats := (select coalesce(jsonb_agg(x || jsonb_build_object('domain', array_position(keys, x ->> 'domain_key') - 1) order by o), '[]') from jsonb_array_elements(flats) with ordinality a(x, o));
  unt := (select coalesce(jsonb_agg(x || jsonb_build_object('domain', array_position(keys, x ->> 'domain_key') - 1) order by o), '[]') from jsonb_array_elements(unt) with ordinality a(x, o));
  shore := (select coalesce(jsonb_agg(x || jsonb_build_object('domain', array_position(keys, x ->> 'domain_key') - 1) order by o), '[]') from jsonb_array_elements(shore) with ordinality a(x, o));

  story := case when st.story_id is not null then jsonb_build_object('story_id', st.story_id, 'archetype', st.archetype, 'archetypes', to_jsonb(st.archetypes),
                  'tier', st.tier, 'engine_tier', st.engine_tier, 'featurable', st.featurable, 'score', round(st.story_score::numeric, 3),
                  'story_sentence', st.copy ->> 'story_sentence', 'conversation_hook', case when quiet then null else st.copy ->> 'conversation_hook' end,
                  'short_title', st.copy ->> 'short_title', 'share_line', st.copy ->> 'share_line', 'derived_by', 'story layer (att_story_candidates)')
                else jsonb_build_object('story_id', null, 'archetype', null, 'archetypes', '[]'::jsonb, 'tier', pl ->> 'weakest_tier', 'engine_tier', null, 'featurable', false, 'score', null,
                  'story_sentence', coalesce(eff -> 0 ->> 'plain', pl ->> 'text_plain'), 'conversation_hook', null,
                  'short_title', name || coalesce(' → ' || (eff -> 0 ->> 'title'), ''), 'share_line', pl ->> 'text_plain',
                  'derived_by', 'rm_pond_payload (no story-layer cascade row for this event)') end;
  travel := coalesce(st.travel, jsonb_build_object('domains_crossed', (select count(distinct x ->> 'domain_key') from jsonb_array_elements(eff) x),
                                                   'days', (select max((x ->> 'lag_days')::int) from jsonb_array_elements(eff) x), 'depth', coalesce((pl ->> 'depth')::int, 0)));
  select jsonb_build_object('hop_id', x -> 'hop_id', 'name', x -> 'name', 'window_start', ev.as_of, 'window_close', x -> 'window_close', 'prior', x -> 'prior',
                            'status', x -> 'status', 'open', not coalesce((x ->> 'window_closed')::boolean, false),
                            'text', case when coalesce((x ->> 'window_closed')::boolean, false)
                                         then 'The window for ' || (x ->> 'name') || ' has closed; the engine is still waiting for enough data to test it.'
                                         else 'Still open: ' || (x ->> 'name') || '. The window closes ' || (x ->> 'window_close') || '.' end)
    into watching from jsonb_array_elements(unt) x order by coalesce((x ->> 'window_closed')::boolean, false), x ->> 'window_close' limit 1;
  honesty := jsonb_build_object('measured_engine', n_meas_eng, 'measured_published', n_meas, 'likely_published', n_like, 'flats', jsonb_array_length(flats),
    'controls_flat', (select count(*) from jsonb_array_elements(ctl) x where x ->> 'tier' = 'flat'), 'watching', jsonb_array_length(unt), 'chains', n_chain,
    'note', n_meas || ' Measured and ' || n_like || ' Likely stop(s) on the published line (tiers after the forecast gate); ' || jsonb_array_length(flats)
            || ' pre-registered series stayed flat; ' || jsonb_array_length(unt) || ' still without a verdict. '
            || case when n_chain = 0 then 'No second-order stop is published, so no chain is drawn. ' else '' end || 'Consistent with, never proof of cause.',
    'quiet', quiet, 'quiet_note', case when quiet then 'Sensitive event: sober copy, no celebration language.' end,
    'control_note', case when ev.role = 'positive_control' then 'A known-effect test case (positive control): the engine is checked on storms like this one, where a move is expected. Published as an archive line with its real, gated tiers.' end);

  out := jsonb_build_object('v', 2, 'version', pv.version, 'snapshot_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'source', 'rm_pond_payload',
    'engine', jsonb_build_object('method_hop', pl ->> 'method', 'method_contrast', case when exists (select 1 from jsonb_array_elements(eff) x where x -> 'contrast' <> 'null') then '6.2.1' end,
                                 'gate_mode', coalesce(ripples._att_cfg('ce') ->> 'gate_mode', 'enforce')),
    'honesty', honesty,
    'event', jsonb_build_object('id', ev.event_id, 'slug', pl -> 'event' ->> 'slug', 'name', name, 'label', lab, 'emoji', pl -> 'event' ->> 'emoji', 'family', ev.family,
                                'sub', 'engine onset ' || to_char(ev.onset, 'FMDD Mon YYYY'), 'onset', ev.onset, 'registered', ev.as_of, 'date', to_char(ev.onset, 'FMDD Mon YYYY'),
                                'magnitude', pl -> 'event' -> 'magnitude_x', 'magnitude_note', case when pl -> 'event' -> 'magnitude_x' = 'null' or pl -> 'event' -> 'magnitude_x' is null then 'not scored; the stone is drawn at the default size' end,
                                'sensitive', quiet, 'role', case when ev.role = 'positive_control' then 'positive_control' else ev.role end,
                                'reconstructed', ev.reconstructed, 'is_control', ev.role = 'positive_control',
                                'cascade', jsonb_build_object('version', pv.version, 'status', pl ->> 'status', 'weakest_tier', pl -> 'weakest_tier', 'denominators', pl -> 'denominators',
                                                              'payload_hash', pl ->> 'payload_hash', 'published_at', pl ->> 'published_at', 'ledger', pl -> 'ledger', 'baseline', pl -> 'event' -> 'baseline', 'method', pl ->> 'method'),
                                'label', true),
    'story', story, 'travel', travel,
    'domains', to_jsonb(array(select coalesce(ripples.rm_domain_word(k), initcap(replace(k, '_', ' '))) from unnest(keys) k)), 'domain_keys', to_jsonb(keys),
    'rings', '[{"days":1,"r":105,"label":"Day 1"},{"days":7,"r":185,"label":"Week 1"},{"days":30,"r":265,"label":"Month 1"},{"days":90,"r":345,"label":"Month 3"}]'::jsonb,
    'effects', eff, 'flats', flats, 'flats_note', jsonb_array_length(flats) || ' series the engine said in advance might move, and did not. Each carries its own fake-date test.',
    'controls', ctl, 'untested', unt, 'shore', shore,
    'rivals', coalesce((select jsonb_agg(jsonb_build_object('name', r ->> 'label', 'event_id', r -> 'event_id', 'note', r ->> 'note',
                                                            'slug', case when ripples.rm_is_public((r ->> 'event_id')::bigint) then ripples.rm_slug((r ->> 'event_id')::bigint) end))
                        from jsonb_array_elements(coalesce(pl -> 'rivals', '[]')) r), '[]'),
    'filtered', coalesce((select jsonb_agg(jsonb_build_object('name', initcap(replace(regexp_replace(cd.c_by_source ->> 'holiday', '^us_', ''), '_', ' ')) || ' (US holiday), ' || to_char(cd.day, 'FMDD Mon'),
                                                              'kind', 'holiday', 'days', jsonb_build_array(cd.day), 'lag_days', cd.day - ev.onset,
                                                              'note', 'A holiday inside the first week. The engine drops common-shock days from its tests.') order by cd.day)
                          from ripples.att_common_days cd where cd.day between ev.onset and ev.onset + 7 and cd.c_by_source ->> 'holiday' is not null), '[]'),
    'watching', watching,
    'pattern_next', case when pnext is not null then pnext || jsonb_build_object('url', '../lands/' || coalesce((select ripples.rm_pond_domain(fe.domain_outcome) from ripples.att_family_effects fe
                                                                                               where fe.grid_id = (pnext ->> 'id')::int order by fe.computed_at desc limit 1), 'real_world') || '/') end,
    'calibration', jsonb_build_object('url', 'v2/calibration.json', 'note', 'decoy false-positive rates and positive-control recall, published daily'),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'day', l.day, 'kind', l.kind, 'ref', l.ref, 'payload_hash', l.payload_hash, 'chain_hash', l.chain_hash) order by l.seq)
                          from ripples.att_ledger l where l.ref ->> 'event_id' = p_event::text or l.seq = any (reg_seqs)), '[]'),
    'ledger_head', (select jsonb_build_object('seq', l.seq, 'chain_hash', l.chain_hash) from ripples.att_ledger l order by l.seq desc limit 1),
    'links', jsonb_build_object('site', 'https://bensunter.com/ripples/pond/?e=' || (pl -> 'event' ->> 'slug'), 'line', 'https://bensunter.com/ripples/line/' || (pl -> 'event' ->> 'slug') || '/',
                                'cascade', 'v2/cascade/' || p_event || '.json', 'csv', case when jsonb_array_length(eff) > 0 then 'v2/hop/' || (eff -> 0 ->> 'hop_id') || '.csv' end,
                                'method', 'https://bensunter.com/ripples/methods/'),
    'changelog', coalesce((select jsonb_agg(jsonb_build_object('version', v.version, 'at', to_char(v.published_at at time zone 'utc', 'YYYY-MM-DD'), 'text', v.payload ->> 'text_plain') order by v.version)
                             from ripples.rm_public_versions v where v.event_id = p_event), '[]'));
  return out;
end $$;
revoke all on function ripples.rm_pond_payload(bigint) from public, anon, authenticated;
revoke all on function ripples.rm_pond_domain(text) from public, anon, authenticated;

-- the pond index: every public line that has a pond payload worth drawing (a Likely+ stop, a flat or a watching stop), flagship first
create or replace function ripples.rm_pond_index() returns jsonb
language sql stable security definer set search_path = '' as $$
  with lat as (select distinct on (v.event_id) v.event_id, v.version, v.payload p from ripples.rm_public_versions v
                 join ripples.att_events e on e.event_id = v.event_id and e.role in ('real','library','positive_control')
                order by v.event_id, v.version desc),
  cfg as (select coalesce((ripples._att_cfg('story') ->> 'flagship_event')::bigint, 213) flagship),
  s as (select distinct on (sc.event_id) sc.event_id, sc.copy, sc.archetype, sc.story_score from ripples.att_story_candidates sc
         where sc.story_kind = 'cascade' and sc.exclude_reason is null order by sc.event_id, sc.featurable desc, sc.story_score desc),
  rows as (
    select lat.event_id, lat.version, lat.p, s.copy, s.archetype, s.story_score,
           (select count(*) from jsonb_array_elements(lat.p -> 'nodes') n where n ->> 'tier' = 'measured') m,
           (select count(*) from jsonb_array_elements(lat.p -> 'nodes') n where n ->> 'tier' = 'likely') l,
           (select count(*) from jsonb_array_elements(lat.p -> 'nodes') n where n ->> 'tier' = 'watching') w,
           jsonb_array_length(coalesce(lat.p -> 'flat', '[]')) f
      from lat left join s on s.event_id = lat.event_id
     where not coalesce(ripples.att_story_off_limits(lat.event_id), false))
  select jsonb_build_object('v', 2, 'as_of', (now() at time zone 'utc')::date,
    'flagship', (select lat.p -> 'event' ->> 'slug' from lat, cfg where lat.event_id = cfg.flagship),
    'ponds', coalesce(jsonb_agg(jsonb_build_object('event_id', r.event_id, 'slug', r.p -> 'event' ->> 'slug',
                 'name', regexp_replace(r.p -> 'event' ->> 'label', '\s*\(positive control\)$', ''), 'label', r.p -> 'event' ->> 'label',
                 'emoji', r.p -> 'event' ->> 'emoji', 'family', r.p -> 'event' ->> 'family', 'onset', r.p -> 'event' ->> 'onset',
                 'sensitive', (r.p -> 'event' ->> 'sensitive')::boolean, 'is_control', (select e.role = 'positive_control' from ripples.att_events e where e.event_id = r.event_id),
                 'version', r.version, 'stops', jsonb_build_object('measured', r.m, 'likely', r.l, 'watching', r.w, 'flat', r.f),
                 'archetype', r.archetype, 'story_sentence', r.copy ->> 'story_sentence', 'url', 'v2/pond/' || (r.p -> 'event' ->> 'slug') || '.json')
               order by (r.event_id = (select flagship from cfg)) desc, r.m desc, r.l desc, r.story_score desc nulls last, r.event_id), '[]'),
    'note', 'Consistent with, never proof of cause.')
    from rows r
$$;
revoke all on function ripples.rm_pond_index() from public, anon, authenticated;

-- public wrapper: index when p_slug is null; one payload otherwise; null when not public, unknown, or anything would leak
create or replace function public.rm_pond(p_slug text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare e bigint; out jsonb;
begin
  if p_slug is null then return ripples.rm_pond_index(); end if;
  e := ripples.rm_event_from_slug(p_slug);
  if e is null then return null; end if;
  out := ripples.rm_pond_payload(e);
  if out is null or cardinality(ripples.rm_label_leaks(out, array['node','id','slug','url','story_id','payload_hash','ledger','template','spark','band','series',
                                                             'licences','sources','geo','code','family','sub','kind','archetype','chain_hash','frozen_hash',
                                                             'domain_key','domain_keys','treated','grid','ref','outcome','links','csv','sample_events'])) > 0 then
    return null;
  end if;
  return out;
end $$;
revoke all on function public.rm_pond(text) from public;
grant execute on function public.rm_pond(text) to anon, authenticated;

-- ---------------------------------------------------------------- p3: positive control as a public story (owner's flagship)
create or replace function ripples.rm_story_public_control(p_event bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_event = any (array(select jsonb_array_elements_text(ripples._att_cfg('story') -> 'public_controls'))::bigint[]), false)
         and ripples.rm_is_public(p_event)
$$;
revoke all on function ripples.rm_story_public_control(bigint) from public, anon, authenticated;
-- att_config story: public_controls [213], flagship_event 213. rm_stories_content (anchor-replaced):
--   and coalesce((s.sensitivity ->> 'is_control')::boolean, false) = false
--   → and (coalesce((s.sensitivity ->> 'is_control')::boolean, false) = false or ripples.rm_story_public_control(s.event_id))
-- att_test_story T37 (anchor-replaced): "controls never featured" → "controls never featured unless allowlisted and public".

-- ---------------------------------------------------------------- p4: contract test + grants
-- rm_pond_contract_test(): the flagship payload against fixture 'pond.json' (contract/fixtures/v2/pond.json), the index, leak guard
-- on every published pond, tier honesty (effects' tiers = the published version's node tiers; Measured only where the gate says so),
-- and that no control other than the allowlisted one appears.
-- rm_grant_audit(): 'rm_pond' added to the anon allowlist.

create or replace function ripples.rm_pond_contract_test() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare fx jsonb; fxi jsonb; idx jsonb; flag jsonb; diffs jsonb := '[]'; idiffs jsonb; cov jsonb; r record; j jsonb; nulls jsonb := '[]'; bad_tier jsonb := '[]';
        bad_gate jsonb := '[]'; bad_ctl jsonb := '[]'; n int := 0; opt text[] := array['contrast','chart','watching','pattern_next','story','fluke','replication','story_replication','ref'];
begin
  select payload - '_comment' into fx from ripples.rm_contract_fixtures where name = 'pond.json';
  select payload - '_comment' into fxi from ripples.rm_contract_fixtures where name = 'pond-index.json';
  idx := public.rm_pond(null);
  select coalesce(jsonb_agg(x), '[]') into idiffs from ripples.rm_shape_diff(fxi, idx, '$', '{}', '{}') x;
  flag := public.rm_pond(idx ->> 'flagship');
  select jsonb_build_object('compared', count(*) filter (where c.state = 'compared'), 'vacuous', count(*) filter (where c.state = 'vacuous'),
                            'vacuous_paths', coalesce((select jsonb_agg(p) from (select c2.path p from ripples.rm_shape_cover(fx, flag) c2 where c2.state = 'vacuous' order by 1 limit 12) z), '[]'))
    into cov from ripples.rm_shape_cover(fx, flag) c;
  for r in select x ->> 'slug' slug, (x ->> 'event_id')::bigint e from jsonb_array_elements(idx -> 'ponds') x limit 60 loop
    n := n + 1;
    j := public.rm_pond(r.slug);
    if j is null then nulls := nulls || to_jsonb(r.slug); continue; end if;
    diffs := diffs || coalesce((select jsonb_agg(r.slug || ' ' || x) from ripples.rm_shape_diff(ripples.rm_strip(fx, array['ref']), ripples.rm_strip(j, array['ref']), '$', '{}', opt) x), '[]');
    -- every effect carries exactly the published version's tier, and only Likely-or-better
    bad_tier := bad_tier || coalesce((select jsonb_agg(r.slug || ' h' || (ef ->> 'hop_id'))
       from jsonb_array_elements(j -> 'effects') ef
      where ef ->> 'tier' not in ('measured','likely')
         or ef ->> 'tier' is distinct from (select nd ->> 'tier' from ripples.rm_public_versions v, jsonb_array_elements(v.payload -> 'nodes') nd
                                              where v.event_id = r.e and (nd ->> 'hop_id') = (ef ->> 'hop_id') order by v.version desc limit 1)), '[]');
    -- a Measured effect only where the forecast gate says Measured
    bad_gate := bad_gate || coalesce((select jsonb_agg(r.slug || ' h' || (ef ->> 'hop_id')) from jsonb_array_elements(j -> 'effects') ef
      where ef ->> 'tier' = 'measured' and ripples.att_ce_gate((ef ->> 'hop_id')::bigint, 'measured') ->> 'tier' <> 'measured'), '[]');
    if coalesce((j -> 'event' ->> 'is_control')::boolean, false) and not ripples.rm_story_public_control(r.e) then bad_ctl := bad_ctl || to_jsonb(r.slug); end if;
    if exists (select 1 from jsonb_array_elements(j -> 'flats') f where f ->> 'tier' <> 'flat') then bad_tier := bad_tier || to_jsonb(r.slug || ' flats'); end if;
  end loop;
  return jsonb_build_object('has_fixture', fx is not null and fxi is not null, 'ponds', n, 'flagship', idx ->> 'flagship', 'index_diffs', idiffs, 'diffs', diffs,
    'coverage', cov, 'null_or_leaking', nulls, 'tier_mismatch', bad_tier, 'measured_without_gate', bad_gate, 'control_not_allowlisted', bad_ctl,
    'ok', fx is not null and fxi is not null and flag is not null and jsonb_array_length(idiffs) = 0 and jsonb_array_length(diffs) = 0 and jsonb_array_length(nulls) = 0
          and jsonb_array_length(bad_tier) = 0 and jsonb_array_length(bad_gate) = 0 and jsonb_array_length(bad_ctl) = 0);
end $$;
revoke all on function ripples.rm_pond_contract_test() from public, anon, authenticated;

-- grant allowlist: rm_pond is a public read RPC (rm_enforce_grants() would revoke it otherwise). Keeps ENGINE 6.3's
-- rm_patterns63 / rm_hunches (migration att_engine_63_p3b_grant_audit_allowlist) — reinstated in rm_integration_p4b after p4 overwrote them.
create or replace function ripples.rm_grant_audit() returns table(fn text, role text)
language sql stable security definer set search_path = '' as $$
  select p.oid::regprocedure::text, r.rolname::text
    from pg_catalog.pg_proc p cross join (values ('anon'), ('authenticated')) r(rolname)
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'rm\_%' or p.proname like 'ripples\_%')
     and p.proname not in ('rm_shocks','rm_cascade','rm_hop','rm_lands','rm_archive','rm_week','rm_calibration','rm_health','rm_event',
                           'ripples_latest','ripples_puzzle','ripples_reveal','ripples_callit','ripples_board','ripples_archive',
                           'ripples_brief','ripples_health','ripples_join','ripples_track_record',
                           'rm_patterns','rm_hop_fx62','rm_patterns63','rm_hunches',
                           'rm_stories',
                           'rm_pond')
     and pg_catalog.has_function_privilege(r.rolname, p.oid, 'EXECUTE')
   order by 1, 2
$$;

-- ---------------------------------------------------------------- p5: publish stays inside the API statement timeout
-- PostgREST runs service_role RPCs under the authenticator's statement_timeout (8 s). With the 30 library lines published on
-- 2026-09-26 one rm_publish_bundle_v2 call measured 9.8 s (freeze 4.1 s for 39 lines at ~0.1 s each; HopEvidence mirror ~5-10 s
-- for ~220 hops of 36 running lines). ripples-publish now:
--   1. freezes in chunks: public.rm_publish_freeze_v2(as_of, events, cap) until `done` (state in att_state 'rm.freeze.run');
--   2. calls rm_publish_bundle_v2, which reuses that freeze result when it is fresh (< 15 min, same as_of and events) instead of
--      freezing again, and — with att_config publish.hops_external = true — returns only `hop_ids` (prioritised, capped) instead
--      of the HopEvidence documents;
--   3. fetches the hop documents in chunks: public.rm_publish_hops_v2(hop_ids[]) (marks them mirrored).
-- Both new RPCs are service-only (no anon / authenticated EXECUTE), like rm_publish_bundle_v2.
create or replace function public.rm_publish_freeze_v2(p_as_of date default null, p_events bigint[] default null, p_cap int default 15) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d date := coalesce(p_as_of, (now() at time zone 'utc')::date); fr jsonb; st jsonb; fresh jsonb; n_new int;
begin
  fr := ripples.att_publish_cascades(d, p_events, greatest(coalesce(p_cap, 15), 1));
  select v into st from ripples.att_state where k = 'rm.freeze.run';
  if st is null or st ->> 'as_of' <> d::text or (st ->> 'at')::timestamptz < now() - interval '15 minutes'
     or (st -> 'events') is distinct from coalesce(to_jsonb(p_events), 'null'::jsonb) then
    st := jsonb_build_object('as_of', d, 'events', coalesce(to_jsonb(p_events), 'null'::jsonb), 'lines', '[]'::jsonb, 'seen', '[]'::jsonb, 'started', now());
  end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into fresh from jsonb_array_elements(fr -> 'lines') x where not (st -> 'seen') @> jsonb_build_array(x -> 'event_id');
  n_new := jsonb_array_length(fresh);
  st := st || jsonb_build_object('at', now(), 'lines', (st -> 'lines') || fresh,
                                 'seen', (st -> 'seen') || coalesce((select jsonb_agg(x -> 'event_id') from jsonb_array_elements(fresh) x), '[]'::jsonb),
                                 'result', fr - 'lines');
  insert into ripples.att_state(k, v) values ('rm.freeze.run', st) on conflict (k) do update set v = excluded.v, updated_at = now();
  return jsonb_build_object('as_of', d, 'processed', jsonb_array_length(fr -> 'lines'), 'fresh', n_new, 'candidates', fr -> 'candidates',
                            'seen', jsonb_array_length(st -> 'seen'), 'new_versions', (select count(*) from jsonb_array_elements(st -> 'lines') x where x ->> 'unchanged' = 'false'),
                            'done', n_new = 0 or jsonb_array_length(st -> 'seen') >= coalesce((fr ->> 'candidates')::int, 0));
end $$;
revoke all on function public.rm_publish_freeze_v2(date, bigint[], int) from public, anon, authenticated;
grant execute on function public.rm_publish_freeze_v2(date, bigint[], int) to service_role;

create or replace function public.rm_publish_hops_v2(p_hops bigint[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ids bigint[]; out jsonb;
begin
  -- only hops that are on a public line's latest version (nodes or flat), at most 50 per call
  select array_agg(h order by h) into ids from (
    select distinct h from unnest(coalesce(p_hops, '{}')) h
     where exists (select 1 from (select distinct on (v.event_id) v.payload from ripples.rm_public_versions v order by v.event_id, v.version desc) lv,
                        lateral (select (n ->> 'hop_id')::bigint id from jsonb_array_elements(lv.payload -> 'nodes') n
                                 union all select (n ->> 'hop_id')::bigint from jsonb_array_elements(coalesce(lv.payload -> 'flat', '[]'::jsonb)) n) x
                    where x.id = h)
     limit 50) z;
  select coalesce(jsonb_agg(jsonb_build_object('hop_id', h, 'json', ripples.rm_hop_evidence(h)::text, 'csv', ripples.rm_hop_csv(h)) order by h), '[]'::jsonb)
    into out from unnest(coalesce(ids, '{}')) h;
  insert into ripples.rm_hop_mirrored(hop_id, mirrored_at) select h, now() from unnest(coalesce(ids, '{}')) h
  on conflict (hop_id) do update set mirrored_at = excluded.mirrored_at;
  return out;
end $$;
revoke all on function public.rm_publish_hops_v2(bigint[]) from public, anon, authenticated;
grant execute on function public.rm_publish_hops_v2(bigint[]) to service_role;

-- rm_publish_bundle_v2 (live definition, anchor-replaced):
--   declare …                                   → declare fst jsonb; …
--   fr := ripples.att_publish_cascades(d, p_events);
--     → reuse att_state 'rm.freeze.run' when fresh (then delete it), else freeze as before
--   the HopEvidence select + rm_hop_mirrored insert → skipped when att_config publish.hops_external (hops = [])
--   'hops', hops,                                → 'hops', hops, 'hop_ids', <hop_ids when hops_external>,
insert into ripples.att_config(key, value) values ('publish', jsonb_build_object('hops_external', true,
  'note', 'ripples-publish fetches HopEvidence through rm_publish_hops_v2 in chunks; freezes through rm_publish_freeze_v2 in chunks'))
on conflict (key) do update set value = ripples.att_config.value || excluded.value, updated_at = now();
