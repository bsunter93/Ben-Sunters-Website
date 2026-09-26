-- =====================================================================================================================
-- 26_att_archive_backfill.sql — WS-E (Ripple Map v6): the reconstructed Ripple Archive
--
-- What this file owns (ws_v6.json WS-E):
--   * the library driver: which att_family_events are run through WS-B's engine in library mode (att_run_library, the same
--     freeze / test / finalize code as the live day), in what order, under which storage guard; results per event;
--   * reconstructed flags and the time split, as labels (the split itself is WS-A's trigger _att_family_events_sets);
--   * positive-control fixtures pointed at the geo-annotated control events (a fixture change, recorded as a model_version
--     ledger row; no threshold is touched);
--   * the archive publication set (≥ 12 reconstructed lines, frozen as versions) and its selection rule;
--   * the Ripple-of-the-week rule (rm_week source: att_week_editions) and the cold-start hero pick;
--   * the archive section of the calibration payload (Σ expected flukes, decoy FDR over the archive, controls, retrospective
--     replication table).
--
-- Honesty rules carried in every object here:
--   * Every archive line is reconstructed = true AND retrospective: the v6.0 mechanism templates, family mappers and library
--     selection rules were written on 2026-09-25 with these events visible (see 18_att_mech_graph.sql / 19_att_families.sql r3).
--     Archive results are "reconstructed", never "predicted"; replication rows computed on them are labelled retrospective.
--   * Nothing here changes a threshold, a weight or a statistic; tiers come only from WS-B's att_finalize.
--   * Storage: att_ingest refuses collector writes above db_cap_mb − 10 (400 − 10 MB on the free profile). The driver stops at
--     att_config 'archive'.db_guard_mb (default 360 MB) so the archive can never starve the collectors.
-- Applied as migrations att_wse_archive_core (+ addenda listed at the end).
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Config
-- ---------------------------------------------------------------------------------------------------------------------
insert into ripples.att_config(key, value) values ('archive', jsonb_build_object(
  'selection_version', 'wse-2',
  'db_guard_mb', 360,                         -- stop running library events above this whole-DB size (collectors stop at 390)
  'skip_utc', jsonb_build_array('05:40', '08:50'),   -- never during the nightly zvec build or the live morning pipeline
  'prior_caps', jsonb_build_object(           -- pre-2026 prior-set sample per family (largest magnitude first; onset ≥ 2020-01-20
    'hazard.storm', 20, 'hazard.heat', 10,    -- so the multi-year baselines exist); media.* and tech.software_release are not
    'hazard.cold', 6, 'hazard.flood', 4,      -- sampled: their outcome series (anilist, steamspy, apple.rss, SE) have no history
    'hazard.wildfire', 4, 'hazard.quake', 4,  -- before 2025-08 and their topics carry no package keys, so every candidate would
    'policy.macro_release', 12, 'tech.model_release', 10),   -- resolve waiting_series
  'publish_min', 12))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. The plan: one row per library / positive-control event the archive will run, with its priority and outcome
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_archive_plan (
  event_id    bigint primary key references ripples.att_events,
  priority    int not null,                  -- lower runs first
  tier        text not null check (tier in ('control','holdout','prior','twin')),
  reason      text not null,
  status      text not null default 'queued' check (status in ('queued','done','failed','excluded')),
  attempts    int not null default 0,
  result      jsonb,
  db_mb_after real,
  planned_at  timestamptz not null default now(),
  ran_at      timestamptz
);
alter table ripples.att_archive_plan enable row level security;
revoke all on ripples.att_archive_plan from public, anon, authenticated;

-- Run order (wse-2). Each library group costs ~0.4 MB and ~2–6 min of DB time on the 2,555-day arrays, and the storage guard
-- allows only a few dozen groups, so the order is what the archive can afford first: controls; grid-demand families (heat, cold:
-- EIA-930 BAs with multi-year history); storms (TSA / FEMA / claims); macro releases (FRED rates); model releases (npm); then the
-- families whose outcome series are short (floods, quakes, wildfires: FEMA / IEM). Hold-out before prior within a family.
create or replace function ripples.att_archive_priority(p_tier text, p_family text, p_rank int) returns int
language sql immutable set search_path = '' as $$
  select 100 * (case p_family when 'hazard.heat' then 1 when 'hazard.cold' then 1 when 'hazard.storm' then 2 when 'policy.macro_release' then 3
                              when 'tech.model_release' then 4 when 'hazard.flood' then 5 when 'hazard.quake' then 6 else 7 end)
         + case when p_tier = 'holdout' then 0 else 50 end + least(coalesce(p_rank, 0), 49)
$$;

-- Deterministic plan builder. Idempotent: existing rows keep their status; new events are appended.
--   P0  control : the geo-annotated positive-control events (WS-A, lib_source 'ENGINE §5.6.4'), which carry state / BA meta
--   P1  holdout : every retrospective hold-out event (onset 2026-01-01 … prereg cutoff) not yet run, non-wildfire first
--   P2  prior   : a capped, magnitude-ranked sample of pre-2026 prior-set events per family (config prior_caps)
--   twin        : control twins created by att_run_positive_control without geo meta (excluded from every archive surface)
create or replace function ripples.att_archive_plan_build() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := coalesce(ripples._att_cfg('archive'), '{}'::jsonb); n0 int; n1 int; n2 int; nt int; v_seq bigint;
begin
  -- P0: geo-annotated positive controls
  insert into ripples.att_archive_plan(event_id, priority, tier, reason)
  select e.event_id, 0, 'control', 'positive control (ENGINE §5.6.4), geo meta ' || coalesce(t.meta ->> 'state', '[]')
  from ripples.att_events e join ripples.att_topics t on t.topic_id = e.topic_id
  where e.role = 'positive_control' and e.reconstructed and t.meta ->> 'lib_source' = 'ENGINE §5.6.4'
  on conflict (event_id) do nothing;
  get diagnostics n0 = row_count;
  -- twins: positive_control events whose topic has no lib_source (created from the fixture label, no state / BA meta)
  insert into ripples.att_archive_plan(event_id, priority, tier, reason, status)
  select e.event_id, 99, 'twin', 'positive-control twin without geo meta (created by att_run_positive_control from the fixture label); superseded by the geo-annotated control event', 'excluded'
  from ripples.att_events e join ripples.att_topics t on t.topic_id = e.topic_id
  where e.role = 'positive_control' and coalesce(t.meta ->> 'lib_source', '') <> 'ENGINE §5.6.4'
  on conflict (event_id) do update set tier = 'twin', status = 'excluded', reason = excluded.reason;
  get diagnostics nt = row_count;
  -- P1: retrospective hold-out
  insert into ripples.att_archive_plan(event_id, priority, tier, reason, status)
  select fe.event_id,
         ripples.att_archive_priority('holdout', fe.family, 0),
         'holdout', 'retrospective hold-out (onset ≥ prior_cutoff, ≤ prereg cutoff): ' || fe.family,
         case when exists (select 1 from ripples.att_hop_candidates c where c.event_id = fe.event_id) then 'done' else 'queued' end
  from ripples.att_family_events fe join ripples.att_events e on e.event_id = fe.event_id
  where fe.in_retro_holdout and e.role = 'library' and e.reconstructed
  on conflict (event_id) do nothing;
  get diagnostics n1 = row_count;
  -- P2: capped prior-set sample, largest magnitude first, then most recent (macro / model releases have no magnitude)
  insert into ripples.att_archive_plan(event_id, priority, tier, reason, status)
  select x.event_id, ripples.att_archive_priority('prior', x.family, x.rk), 'prior', 'prior-set sample (' || x.family || ', rank ' || x.rk || ' of cap ' || x.cap || ')',
         case when exists (select 1 from ripples.att_hop_candidates c where c.event_id = x.event_id) then 'done' else 'queued' end
  from (select fe.event_id, fe.family, (cfg -> 'prior_caps' ->> fe.family)::int cap,
               row_number() over (partition by fe.family order by fe.magnitude desc nulls last, fe.onset desc, fe.event_id) rk
        from ripples.att_family_events fe join ripples.att_events e on e.event_id = fe.event_id
        where fe.in_prior_set and e.role = 'library' and e.reconstructed and fe.onset >= date '2020-01-20'
          and (cfg -> 'prior_caps') ? fe.family) x
  where x.rk <= x.cap
  on conflict (event_id) do nothing;
  get diagnostics n2 = row_count;
  if n0 + n1 + n2 + nt > 0 then
    v_seq := ripples.att_ledger_append(current_date, 'model_version',
               jsonb_build_object('archive_selection', cfg ->> 'selection_version'),
               jsonb_build_object('archive_selection', cfg ->> 'selection_version', 'config', cfg,
                                  'plan', (select jsonb_agg(jsonb_build_array(event_id, priority, tier) order by event_id) from ripples.att_archive_plan)));
  end if;
  return jsonb_build_object('control', n0, 'holdout', n1, 'prior', n2, 'twins', nt, 'ledger_seq', v_seq,
                            'queued', (select count(*) from ripples.att_archive_plan where status = 'queued'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. The driver: one plan row per call, WS-B's att_run_library (identical freeze / test / finalize code), guarded
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_archive_step() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := coalesce(ripples._att_cfg('archive'), '{}'::jsonb); p record; r jsonb; t0 timestamptz := clock_timestamp();
        db_mb real := pg_database_size(current_database()) / 1048576.0; rc jsonb := ripples.att_state_get('engine.recompute');
        zv jsonb := ripples.att_state_get('zvec.run'); now_t time := (now() at time zone 'utc')::time;
begin
  if now_t between coalesce((cfg -> 'skip_utc' ->> 0)::time, '05:40') and coalesce((cfg -> 'skip_utc' ->> 1)::time, '08:50') then
    return jsonb_build_object('skipped', 'nightly zvec / live morning window');
  end if;
  if db_mb > coalesce((cfg ->> 'db_guard_mb')::real, 360) then
    return jsonb_build_object('skipped', 'db guard', 'db_mb', round(db_mb::numeric, 1), 'guard', cfg ->> 'db_guard_mb');
  end if;
  -- never run on half-rebuilt arrays or while WS-B's recompute re-runs pre-registered looks
  if rc is not null and not (rc ? 'finished') then return jsonb_build_object('skipped', 'engine recompute in progress'); end if;
  if zv is not null and not (zv ? 'finished') then return jsonb_build_object('skipped', 'zvec rebuild in progress'); end if;
  select * into p from ripples.att_archive_plan where status = 'queued' and attempts < 3 order by priority, event_id limit 1;
  if not found then return jsonb_build_object('idle', true); end if;
  update ripples.att_archive_plan set attempts = attempts + 1 where event_id = p.event_id;
  begin
    r := ripples.att_run_library(p.event_id);
  exception when others then
    update ripples.att_archive_plan set status = case when attempts >= 3 then 'failed' else 'queued' end,
           result = jsonb_build_object('error', left(sqlerrm, 300), 'at', now()) where event_id = p.event_id;
    return jsonb_build_object('event_id', p.event_id, 'error', left(sqlerrm, 300));
  end;
  update ripples.att_archive_plan set status = 'done', ran_at = now(),
         result = jsonb_build_object('looks_ran', r -> 'looks_ran', 'final_day', r -> 'final_day', 'finalize', r -> 'finalize',
                                     'decoys_created', r -> 'decoys_created', 'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)),
         db_mb_after = pg_database_size(current_database()) / 1048576.0
   where event_id = p.event_id;
  return jsonb_build_object('event_id', p.event_id, 'tier', p.tier, 'looks_ran', r -> 'looks_ran',
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- Shares WS-B's library-stepper lock, so the archive driver and att_library_step never run two library events at once
create or replace function ripples.att_archive_step_locked() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not pg_try_advisory_lock(hashtext('ripples.att_library_step')) then return jsonb_build_object('skipped', 'library lock held'); end if;
  begin
    r := ripples.att_archive_step();
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
  return r;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2b. Look stepper (ops, added 2026-09-26 00:20 UTC). WS-B's recompute (att_recompute_step) re-runs every pre-registered
--     reconstructed look inside ONE transaction per call: its first group's att_engine_run_due(day) picks up every pending
--     reconstructed look up to that day (7,289 looks after the fix-4 reset), which cannot finish inside a 15 (or 50) minute
--     timeout on the 2,555-day arrays, never commits, and holds att_sd_null / att_hop_tests row locks that block every other
--     engine call. This stepper runs the SAME function (att_engine_run_due, reconstructed = true) on the earliest pending look
--     day, in committed chunks of p_budget_s seconds, so each hop's looks run in date order exactly as in the recompute. When
--     nothing is pending, WS-B's att_recompute_step only has finalize / chain / cascade work left per group and fits its timeout.
--     Nothing about a look, a threshold or a result changes; only the transaction boundaries do.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_archive_looks_step(p_budget_s int default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d date; r jsonb; t0 timestamptz := clock_timestamp(); n_ran int := 0; n_days int := 0; last_day date; now_t time := (now() at time zone 'utc')::time;
begin
  if now_t between time '05:40' and time '08:50' then return jsonb_build_object('skipped', 'nightly zvec / live morning window'); end if;
  if not pg_try_advisory_lock(hashtext('ripples.att_library_step')) then return jsonb_build_object('skipped', 'library lock held'); end if;
  begin
    loop
      exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
      select min(u.d) into d
        from ripples.att_hop_candidates c, unnest(c.looks) with ordinality u(d, o)
       where c.frozen_hash is not null and c.status <> 'skipped' and c.reconstructed and u.d <= current_date
         and not exists (select 1 from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.look_no = u.o and (t.t_stat is not null or t.tier_reason = 'waiting_series'));
      exit when d is null;
      exit when d is not distinct from last_day and coalesce((r ->> 'ran')::int, 0) = 0;   -- no progress on this day: stop, report
      r := ripples.att_engine_run_due(d, 100000, true, greatest(1, p_budget_s - extract(epoch from clock_timestamp() - t0)::int));
      n_ran := n_ran + (r ->> 'ran')::int; n_days := n_days + 1; last_day := d;
    end loop;
  exception when others then
    perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
    raise;
  end;
  perform pg_advisory_unlock(hashtext('ripples.att_library_step'));
  perform ripples.att_state_set('wse.looks_step', coalesce(ripples.att_state_get('wse.looks_step'), '{}'::jsonb)
          || jsonb_build_object('day', coalesce(d, last_day), 'idle', d is null, 'at', now(), 'last_ran', n_ran, 'days', n_days,
                                'ran_total', coalesce((ripples.att_state_get('wse.looks_step') ->> 'ran_total')::int, 0) + n_ran));
  return jsonb_build_object('ran', n_ran, 'days', n_days, 'day', coalesce(d, last_day), 'idle', d is null,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Labels: sensitive (quiet mode) for harmful hazards; reconstructed is already true on every library / control event
-- ---------------------------------------------------------------------------------------------------------------------
-- Quiet mode (EXPERIENCE §2, §8): hazards with harm render without flips, Shock-of-the-day cards or share GIFs. Every FEMA-declared
-- storm / flood / wildfire, every heat or cold event and every quake of M ≥ 5.0 in the archive is marked sensitive. Small felt
-- quakes (M < 5, no declaration) are not.
create or replace function ripples.att_archive_sensitive() returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update ripples.att_events e set sensitive = true
   where e.reconstructed and e.role in ('library','positive_control') and not e.sensitive
     and (e.family in ('hazard.storm','hazard.flood','hazard.wildfire','hazard.heat','hazard.cold')
          or (e.family = 'hazard.quake' and coalesce(substring(e.label from '^M([0-9]+\.[0-9])')::numeric, 0) >= 5.0));
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Positive controls: point the fixtures at the geo-annotated control events (fixture change, ledger model_version row)
-- ---------------------------------------------------------------------------------------------------------------------
-- att_run_positive_control resolves its event through att_library_event(qid, label, family, onset, 'positive_control'), which
-- matches on (qid = p_qid or label = p_label). The fixtures carried the bare label ("Hurricane Helene"), so the gate created
-- twins without state / BA meta: their mappers could not resolve eia.930:ERCO, fema.decl:st:FL, … and the controls could never
-- test the nodes they expect. The fixtures now carry the control event's own label and qid (null), so the gate reuses it.
-- Llama 3 / DeepSeek-R1 expected pypi.dl:transformers and hf.trending:models, which keep no history before 2025-08 (pypistats
-- 180-day API, HF trending snapshots): they could never be tested. ENGINE §5.6.4 names "hf.trending/npm/pypi"; the fixtures now
-- expect the npm packages with backfilled history (npm.dl:ollama, npm.dl:openai, npm.dl:langchain; any of). No threshold changes.
create or replace function ripples.att_archive_controls_fix() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k record; ev record; n int := 0; changes jsonb := '[]'::jsonb; v_seq bigint; new_spec jsonb;
begin
  for k in select * from ripples.att_controls where kind = 'positive' order by id loop
    select e.* into ev from ripples.att_events e where e.event_id = (k.spec ->> 'event_id')::bigint and e.role = 'positive_control';
    if not found then continue; end if;
    new_spec := k.spec || jsonb_build_object('label', ev.label, 'qid', ev.qid);
    if k.spec ->> 'name' in ('Llama 3 release → HF / npm / pypi', 'DeepSeek-R1 release → HF / pypi') then
      new_spec := new_spec || jsonb_build_object('expect', jsonb_build_array('npm.dl:ollama', 'npm.dl:openai', 'npm.dl:langchain'),
                  'expect_was', k.spec -> 'expect',
                  'expect_note', 'pypi.dl and hf.trending keep no history before 2025-08; npm packages backfilled from 2022-06 (WS-E fixture change)');
    end if;
    if new_spec is distinct from k.spec then
      update ripples.att_controls set spec = new_spec where id = k.id;
      changes := changes || jsonb_build_object('id', k.id, 'name', k.spec ->> 'name', 'label', ev.label, 'event_id', ev.event_id,
                                               'expect', new_spec -> 'expect');
      n := n + 1;
    end if;
  end loop;
  if n > 0 then
    v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('controls_fixture', 'wse-1'),
               jsonb_build_object('controls_fixture', 'wse-1', 'changes', changes,
                                  'note', 'fixture targets only; no threshold, weight or statistic changed'));
  end if;
  return jsonb_build_object('changed', n, 'changes', changes, 'ledger_seq', v_seq);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Archive lines: one summary row per reconstructed line (from the latest att_cascades payload)
-- ---------------------------------------------------------------------------------------------------------------------
-- EXPERIENCE §3 has eight domains; WS-B's att_domain_of returns finer codes. Map them for counting.
create or replace function ripples.att_domain8(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'search' then 'reading' when 'social' then 'chatter' when 'news' then 'chatter' when 'economy' then 'markets'
                when 'consumption' then 'stuff' else p end
$$;

create or replace view ripples.att_archive_lines with (security_invoker = true) as
select e.event_id, e.slug, e.label, e.family, e.onset, e.role, e.sensitive, e.status, e.reconstructed, fe.evidence_mode, fe.set_note,
       c.version, c.payload_hash, c.updated_at,
       coalesce((c.denominators ->> 'tested')::int, 0) tested,
       (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome'
          and not coalesce((n ->> 'attention_ripple')::boolean, false)) measured_outcome,
       (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured') measured,
       (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'likely') likely,
       (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'watching') watching,
       (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'retracted') retracted,
       jsonb_array_length(coalesce(c.payload -> 'flat', '[]'::jsonb)) flat,
       (select coalesce(jsonb_agg(distinct ripples.att_domain8(n ->> 'domain')), '[]'::jsonb) from jsonb_array_elements(c.payload -> 'nodes') n
          where n ->> 'tier' in ('measured','likely') and not coalesce((n ->> 'attention_ripple')::boolean, false)) domains,
       (select coalesce(jsonb_agg(distinct ripples.att_domain8(n ->> 'domain')), '[]'::jsonb) from jsonb_array_elements(c.payload -> 'nodes') n
          where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome') measured_domains,
       (select max((n ->> 'hidden')::real) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured') hidden_max,
       (c.payload -> 'denominators' ->> 'expected_false_links')::real sum_f,
       c.payload
from ripples.att_events e
join ripples.att_cascades c on c.event_id = e.event_id
left join ripples.att_family_events fe on fe.event_id = e.event_id
where e.reconstructed and e.role in ('library','positive_control')
  and not exists (select 1 from ripples.att_archive_plan p where p.event_id = e.event_id and p.tier = 'twin');
revoke all on ripples.att_archive_lines from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Publishing a version (frozen, immutable). Delegates to WS-C's att_publish_cascade(event) when it exists; otherwise
--    freezes att_cascade_versions itself with the same rule (a new version only when the payload hash changed) and a ledger
--    'version_publish' row. Storage mirroring and OG pre-render are WS-C's ripples-publish, which reads att_cascade_versions.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_archive_freeze_version(p_event bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; last record; k int; v_payload jsonb; v_seq bigint; r jsonb;
begin
  if to_regprocedure('ripples.att_publish_cascade(bigint)') is not null then
    execute 'select ripples.att_publish_cascade($1)' into r using p_event;
    return jsonb_build_object('event_id', p_event, 'via', 'att_publish_cascade', 'result', r);
  end if;
  select * into c from ripples.att_cascades where event_id = p_event;
  if not found then return jsonb_build_object('event_id', p_event, 'error', 'no cascade payload'); end if;
  if not exists (select 1 from ripples.att_events where event_id = p_event and role in ('library','positive_control','real')) then
    return jsonb_build_object('event_id', p_event, 'error', 'decoy events are never published by id');
  end if;
  select * into last from ripples.att_cascade_versions where event_id = p_event order by version desc limit 1;
  if found and last.payload_hash = c.payload_hash then
    return jsonb_build_object('event_id', p_event, 'version', last.version, 'unchanged', true);
  end if;
  k := coalesce(last.version, 0) + 1;
  v_payload := c.payload || jsonb_build_object('version', k,
                 'grown_since', case when last.version is not null then jsonb_build_object('version', last.version,
                   'stops_added', greatest(0, (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' in ('measured','likely'))
                                          - (select count(*) from jsonb_array_elements(last.payload -> 'nodes') n where n ->> 'tier' in ('measured','likely')))) end,
                 'text_share', regexp_replace(c.payload ->> 'text_share', '/v[0-9]+/$', '/v' || k || '/'));
  insert into ripples.att_cascade_versions(event_id, version, payload, payload_hash) values (p_event, k, v_payload, c.payload_hash);
  update ripples.att_cascades set version = k where event_id = p_event;
  v_seq := ripples.att_ledger_append(current_date, 'version_publish', jsonb_build_object('event_id', p_event, 'version', k),
                                     jsonb_build_object('event_id', p_event, 'version', k, 'payload_hash', c.payload_hash, 'reconstructed', (c.payload -> 'event' ->> 'reconstructed')::boolean));
  return jsonb_build_object('event_id', p_event, 'version', k, 'payload_hash', c.payload_hash, 'ledger_seq', v_seq);
end $$;

-- The published archive set and why each line is in it
create table if not exists ripples.att_archive_published (
  event_id    bigint primary key references ripples.att_events,
  version     int not null,
  why         text not null,
  measured_outcome int not null,
  domains     jsonb not null,
  status      text not null,
  selected_at timestamptz not null default now(),
  ledger_seq  bigint
);
alter table ripples.att_archive_published enable row level security;
revoke all on ripples.att_archive_published from public, anon, authenticated;

-- Selection rule (published on /methods/ with the archive): closed lines only (ended / nowhere / archived), never a twin;
--   (a) every line with a Measured outcome stop, most Measured stops first, then most domains, then hiddenness;
--   (b) every positive control, whatever its result (a control that failed is shown failing);
--   (c) the lines that went nowhere, largest denominators first, until ≥ 1/3 of the set are duds (the null is the product);
--   (d) every line with a retraction.
-- Capped at p_max lines; at least publish_min.
create or replace function ripples.att_archive_select(p_max int default 24) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; n_dud int := 0; fr jsonb; out jsonb := '[]'::jsonb; v_min int := coalesce((ripples._att_cfg('archive') ->> 'publish_min')::int, 12);
begin
  drop table if exists _sel;
  create temp table _sel on commit drop as select event_id, 'x'::text why, 0 ord from ripples.att_archive_lines where false;
  insert into _sel select event_id, 'positive control (' || case when measured_outcome > 0 then 'Measured' else 'did not reach Measured' end || ')', 1
    from ripples.att_archive_lines where role = 'positive_control' and status <> 'running';
  insert into _sel select l.event_id, 'Measured outcome stop in ' || l.measured_domains::text, 2
    from ripples.att_archive_lines l where l.measured_outcome > 0 and l.status <> 'running' and l.role = 'library'
    order by l.measured_outcome desc, jsonb_array_length(l.domains) desc, l.hidden_max desc nulls last, l.onset desc
    limit greatest(0, p_max - (select count(*) from _sel) - 4);
  insert into _sel select l.event_id, 'retraction on the line', 3
    from ripples.att_archive_lines l where l.retracted > 0 and l.status <> 'running' and not exists (select 1 from _sel s where s.event_id = l.event_id);
  select count(*) into n from _sel;
  insert into _sel select l.event_id, 'went nowhere: ' || l.tested || ' paths tested, none moved', 4
    from ripples.att_archive_lines l where l.status = 'nowhere' and l.tested > 0 and not exists (select 1 from _sel s where s.event_id = l.event_id)
    order by l.tested desc, l.onset desc limit greatest(4, (n + 2) / 2);
  -- fill to the minimum with ended lines (Likely stops only), most stops first
  select count(*) into n from _sel;
  if n < v_min then
    insert into _sel select l.event_id, 'line ended at Likely (no Measured stop)', 5
      from ripples.att_archive_lines l where l.status in ('ended','archived') and not exists (select 1 from _sel s where s.event_id = l.event_id)
      order by l.likely desc, l.onset desc limit v_min - n;
  end if;
  for r in select distinct on (s.event_id) s.event_id, s.why, l.measured_outcome, l.domains, l.status from _sel s join ripples.att_archive_lines l using (event_id) order by s.event_id, s.ord loop
    fr := ripples.att_archive_freeze_version(r.event_id);
    if (fr ->> 'version') is null then continue; end if;
    insert into ripples.att_archive_published(event_id, version, why, measured_outcome, domains, status, ledger_seq)
    values (r.event_id, (fr ->> 'version')::int, r.why, r.measured_outcome, r.domains, r.status, (fr ->> 'ledger_seq')::bigint)
    on conflict (event_id) do update set version = excluded.version, why = excluded.why, measured_outcome = excluded.measured_outcome,
      domains = excluded.domains, status = excluded.status, selected_at = now(), ledger_seq = coalesce(excluded.ledger_seq, ripples.att_archive_published.ledger_seq);
    out := out || jsonb_build_object('event_id', r.event_id, 'version', fr -> 'version', 'why', r.why);
  end loop;
  return jsonb_build_object('published', jsonb_array_length(out), 'lines', out);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Ripple of the week (rm_week source) and the cold-start hero
-- ---------------------------------------------------------------------------------------------------------------------
-- Rule (EXPERIENCE §6, ENGINE §11 rm_week): among the lines whose shock started in the ISO week (live and reconstructed alike,
-- never decoys or control twins): most Measured outcome stops; the line must reach ≥ 3 domains (distinct domains of its
-- non-attention Likely-or-better stops) and have ≥ 1 Measured outcome stop; ties broken by hiddenness (max H of its Measured
-- stops), then by more domains, then earlier onset, then event id. If nothing qualifies the edition says so and shows the best
-- single-stop line (≥ 1 Measured outcome stop, same ordering). If no line has a Measured outcome stop, ripple_of_week is null.
create table if not exists ripples.att_week_editions (
  week        text primary key check (week ~ '^[0-9]{4}-[0-9]{2}$'),   -- ISO 'YYYY-WW'
  edition     int not null,
  event_id    bigint references ripples.att_events,
  version     int,
  qualified   boolean not null,
  note        text,
  payload     jsonb not null,                -- rm_week shape: {week, ripple_of_week, rule, lines, qualified, note, edition, reconstructed}
  created_at  timestamptz not null default now(),
  ledger_seq  bigint
);
alter table ripples.att_week_editions enable row level security;
revoke all on ripples.att_week_editions from public, anon, authenticated;

create or replace function ripples.att_week_bounds(p_week text) returns daterange
language sql immutable set search_path = '' as $$
  select daterange(to_date(p_week || '-1', 'IYYY-IW-ID'), to_date(p_week || '-1', 'IYYY-IW-ID') + 7)
$$;

create or replace function ripples.att_week_pick(p_week text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare wk daterange := ripples.att_week_bounds(p_week); lines jsonb; best record; v_q boolean := false; v_note text; hero jsonb; v_ver int; fr jsonb; e record;
        rule text := 'most Measured stops; ≥ 3 domains; hiddenness breaks ties';
begin
  drop table if exists _wk;
  create temp table _wk on commit drop as
  select e.event_id, e.slug, e.label, e.family, e.onset, e.status, e.reconstructed, e.sensitive, e.role, c.version,
         c.payload -> 'event' ->> 'emoji' emoji, c.payload ->> 'weakest_tier' weakest_tier,
         (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome'
            and not coalesce((n ->> 'attention_ripple')::boolean, false)) m_out,
         (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured') m_all,
         (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'likely') n_lik,
         (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'watching') n_watch,
         jsonb_array_length(coalesce(c.payload -> 'flat', '[]'::jsonb)) n_flat,
         (select coalesce(jsonb_agg(distinct ripples.att_domain8(n ->> 'domain')), '[]'::jsonb) from jsonb_array_elements(c.payload -> 'nodes') n
            where n ->> 'tier' in ('measured','likely') and not coalesce((n ->> 'attention_ripple')::boolean, false)) doms,
         (select max((n ->> 'hidden')::real) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured') h
  from ripples.att_events e join ripples.att_cascades c on c.event_id = e.event_id
  where e.onset <@ wk and e.role in ('real','library','positive_control')
    and not exists (select 1 from ripples.att_archive_plan p where p.event_id = e.event_id and p.tier = 'twin');
  select coalesce(jsonb_agg(jsonb_build_object('event_id', event_id, 'slug', slug, 'label', label, 'emoji', emoji, 'family', family, 'onset', onset,
                   'status', status, 'reconstructed', reconstructed, 'sensitive', sensitive,
                   'stops', m_all + n_lik, 'measured', m_all, 'measured_outcome', m_out, 'likely', n_lik, 'watching', n_watch, 'flat', n_flat,
                   'domains', doms, 'weakest_tier', weakest_tier, 'version', version)
                 order by m_out desc, jsonb_array_length(doms) desc, onset, event_id), '[]'::jsonb) into lines from _wk;
  select * into best from _wk where m_out >= 1 and jsonb_array_length(doms) >= 3
   order by m_out desc, h desc nulls last, jsonb_array_length(doms) desc, onset, event_id limit 1;
  if found then
    v_q := true;
  else
    select * into best from _wk where m_out >= 1 order by m_out desc, h desc nulls last, jsonb_array_length(doms) desc, onset, event_id limit 1;
    v_note := case when found then 'Nothing this week reached 3 domains with a Measured stop; showing the best single-stop line.'
                   else 'No line that started this week reached a Measured stop.' end;
  end if;
  -- every line of the week is published (a /week/ page lists only public lines, duds included), the pick first
  if best.event_id is not null then
    fr := ripples.att_archive_freeze_version(best.event_id);
    select version, payload into v_ver, hero from ripples.att_cascade_versions where event_id = best.event_id order by version desc limit 1;
  end if;
  for e in select event_id from _wk where event_id is distinct from best.event_id and role in ('library','positive_control','real') loop
    fr := ripples.att_archive_freeze_version(e.event_id);
  end loop;
  select coalesce(jsonb_agg(x || jsonb_build_object('version', (select max(v.version) from ripples.att_cascade_versions v where v.event_id = (x ->> 'event_id')::bigint))), '[]'::jsonb)
    into lines from jsonb_array_elements(lines) x;
  return jsonb_build_object('week', p_week, 'from', lower(wk), 'to', upper(wk) - 1, 'rule', rule, 'qualified', v_q, 'note', v_note,
                            'ripple_of_week', hero, 'event_id', best.event_id, 'version', v_ver,
                            'reconstructed', coalesce(best.reconstructed, false), 'lines', lines);
end $$;

create or replace function ripples.att_week_edition(p_week text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare w jsonb; n int; v_seq bigint; payload jsonb;
begin
  w := ripples.att_week_pick(p_week);
  select coalesce(max(edition), 0) + 1 into n from ripples.att_week_editions where week < p_week;
  payload := w || jsonb_build_object('v', 2, 'edition', coalesce((select edition from ripples.att_week_editions where week = p_week), n), 'published_at', now());
  v_seq := ripples.att_ledger_append(current_date, 'version_publish', jsonb_build_object('week', p_week),
             jsonb_build_object('week', p_week, 'event_id', w -> 'event_id', 'version', w -> 'version', 'qualified', w -> 'qualified',
                                'lines', (select jsonb_agg(x -> 'event_id') from jsonb_array_elements(w -> 'lines') x)));
  insert into ripples.att_week_editions(week, edition, event_id, version, qualified, note, payload, ledger_seq)
  values (p_week, (payload ->> 'edition')::int, (w ->> 'event_id')::bigint, (w ->> 'version')::int, (w ->> 'qualified')::boolean, w ->> 'note', payload, v_seq)
  on conflict (week) do update set event_id = excluded.event_id, version = excluded.version, qualified = excluded.qualified, note = excluded.note,
    payload = excluded.payload, ledger_seq = excluded.ledger_seq, created_at = now();
  return payload - 'ripple_of_week' - 'lines' || jsonb_build_object('lines', jsonb_array_length(w -> 'lines'), 'ledger_seq', v_seq);
end $$;

-- Cold-start hero (EXPERIENCE §2): the live line with the most Measured outcome stops published in the last 7 days; if none, the
-- best reconstructed archive line by the week rule over the published archive, labelled "From the archive ▪ reconstructed".
-- The headline cites a Measured outcome stop only.
create or replace function ripples.att_hero_pick(p_day date default current_date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h record; stop jsonb; src text;
begin
  select e.event_id, c.version, c.payload, false rec into h
    from ripples.att_events e join ripples.att_cascades c on c.event_id = e.event_id
   where e.role = 'real' and not e.reconstructed and e.as_of between p_day - 7 and p_day
     and exists (select 1 from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome')
   order by (select count(*) from jsonb_array_elements(c.payload -> 'nodes') n where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome') desc, e.as_of desc, e.event_id
   limit 1;
  src := 'live';
  if not found then
    select l.event_id, v.version, v.payload, true rec into h
      from ripples.att_archive_published p join ripples.att_archive_lines l on l.event_id = p.event_id
      join ripples.att_cascade_versions v on v.event_id = p.event_id and v.version = p.version
     where p.measured_outcome > 0
     order by (jsonb_array_length(l.domains) >= 3) desc, p.measured_outcome desc, l.hidden_max desc nulls last, jsonb_array_length(l.domains) desc, l.onset desc
     limit 1;
    src := 'archive';
    if not found then return jsonb_build_object('source', 'none', 'note', 'no Measured outcome stop live or in the archive'); end if;
  end if;
  select n into stop from jsonb_array_elements(h.payload -> 'nodes') n
   where n ->> 'tier' = 'measured' and n ->> 'kind' = 'outcome' order by (n ->> 'depth')::int, (n ->> 'q')::float8 limit 1;
  return jsonb_build_object('source', src, 'reconstructed', h.rec,
    'label', case when src = 'archive' then 'From the archive ▪ reconstructed' end,
    'event_id', h.event_id, 'version', h.version, 'slug', h.payload -> 'event' ->> 'slug', 'title', h.payload -> 'event' ->> 'label',
    'sensitive', (h.payload -> 'event' ->> 'sensitive')::boolean,
    'headline', format('%s later it showed up in %s.',
                       case when (stop ->> 'lag_days')::int = 1 then '1 day' when (stop ->> 'lag_days')::int = 0 then 'The same day,' else (stop ->> 'lag_days') || ' days' end,
                       stop ->> 'label'),
    'stop', jsonb_build_object('hop_id', stop -> 'hop_id', 'label', stop -> 'label', 'domain', ripples.att_domain8(stop ->> 'domain'), 'rho', stop -> 'rho',
                               'lag_days', stop -> 'lag_days', 'p_1_in', stop -> 'p_1_in', 'f_1_in', stop -> 'f_1_in'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Archive calibration section (merged into att_calibration_public; ledger 'calibration' row)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_archive_calibration(p_as_of date default current_date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare fdr jsonb; ctrl jsonb; rep jsonb; meas jsonb; sec jsonb; v_seq bigint; cal_day date; decoy jsonb;
begin
  -- decoy realised FDR over every reconstructed look (library scope; all days)
  fdr := ripples.att_decoy_fdr(p_as_of, 4000, 'library');
  -- decoy events of the archive: Measured stops per decoy event vs per real event (the ENGINE §5.5 event rate)
  select jsonb_build_object(
      'decoy_events', count(distinct c.event_id) filter (where c.role = 'decoy'),
      'decoy_events_with_measured', count(distinct c.event_id) filter (where c.role = 'decoy' and h.tier = 'measured'),
      'real_events', count(distinct c.event_id) filter (where c.role <> 'decoy'),
      'real_events_with_measured', count(distinct c.event_id) filter (where c.role <> 'decoy' and h.tier = 'measured' and ripples.att_series_kind_of_node(c.node) = 'outcome'))
    into decoy
    from ripples.att_hop_candidates c join ripples.att_hop_latest h on h.hop_id = c.hop_id
   where c.reconstructed and c.role in ('real','decoy','library','positive_control')
     and not exists (select 1 from ripples.att_archive_plan p where p.event_id = coalesce((select matched_to from ripples.att_events d where d.event_id = c.event_id and d.role = 'decoy'), c.event_id) and p.tier = 'twin');
  -- Σ expected flukes among the archive's Measured hops (Σ f), and how many Measured
  select jsonb_build_object('measured', count(*), 'measured_outcome', count(*) filter (where ripples.att_series_kind_of_node(h.node) = 'outcome'),
                            'expected_flukes', round(coalesce(sum(h.f), 0)::numeric, 3),
                            'f_missing', count(*) filter (where h.f is null))
    into meas
    from ripples.att_hop_latest h join ripples.att_events e on e.event_id = h.event_id
   where h.reconstructed and h.tier = 'measured' and e.role in ('library','positive_control')
     and not exists (select 1 from ripples.att_archive_plan p where p.event_id = e.event_id and p.tier = 'twin');
  select coalesce(jsonb_agg(jsonb_build_object('name', spec ->> 'name', 'passed', passed, 'last_run', last_run, 'event_id', detail -> 'event_id',
                                               'measured', detail -> 'measured', 'missing', detail -> 'missing') order by id), '[]'::jsonb)
    into ctrl from ripples.att_controls where kind = 'positive';
  select coalesce(jsonb_agg(jsonb_build_object('family', family, 'edge_class', edge_class, 'channel', channel, 'n', n, 'hits', hits,
                                               'p_dose', p_dose, 'route', route, 'one_off', one_off,
                                               'text', format('Seen after %s of %s past %s events (reconstructed, retrospective).', hits, n, replace(family, 'hazard.', '')))
                            order by family, n desc, edge_class), '[]'::jsonb)
    into rep from ripples.att_replication where as_of = (select max(as_of) from ripples.att_replication);
  sec := jsonb_build_object('as_of', p_as_of, 'label', 'reconstructed archive (retrospective: mechanism library and selection rules written 2026-09-25 with these events visible)',
    'lines_run', (select count(*) from ripples.att_archive_plan where status = 'done' and tier <> 'twin'),
    'lines_published', (select count(*) from ripples.att_archive_published),
    'lines', (select count(*) from ripples.att_archive_published),                -- WS-C fixture keys (calibration.json 'archive')
    'expected_false_links', (meas ->> 'expected_flukes')::numeric,
    'measured', meas, 'decoy_fdr', fdr - 'as_of' - 'days', 'decoy_events', decoy, 'controls', ctrl,
    'replication', jsonb_build_object('evidence_mode', 'retrospective', 'note', 'computed on the reconstructed hold-out (onset ≥ 2026-01-01, not preregistered); not a prospective replication', 'rows', rep),
    'sentence', format('Across the reconstructed archive, %s stops reached Measured; about %s of them are expected to be flukes.',
                       meas ->> 'measured', meas ->> 'expected_flukes'));
  select max(as_of) into cal_day from ripples.att_calibration_public;
  if cal_day is null then
    insert into ripples.att_calibration_public(as_of, payload) values (p_as_of, jsonb_build_object('v', 2, 'as_of', p_as_of, 'archive', sec));
    cal_day := p_as_of;
  else
    update ripples.att_calibration_public set payload = payload || jsonb_build_object('archive', sec) where as_of = cal_day;
  end if;
  v_seq := ripples.att_ledger_append(p_as_of, 'calibration', jsonb_build_object('archive', true, 'calibration_as_of', cal_day), sec);
  return sec || jsonb_build_object('ledger_seq', v_seq, 'calibration_as_of', cal_day);
end $$;

-- node → kind (outcome / attention) through its measurement bundle
create or replace function ripples.att_series_kind_of_node(p_node text) returns text
language sql stable set search_path = '' as $$
  select case when exists (select 1 from ripples.att_node_series ns join ripples.att_channel_stat cs on cs.channel = ns.channel
                           where ns.node = p_node and cs.kind = 'outcome') then 'outcome' else 'attention' end
$$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname in ('att_archive_plan_build','att_archive_step','att_archive_step_locked','att_archive_sensitive',
             'att_archive_controls_fix','att_domain8','att_archive_freeze_version','att_archive_select','att_week_bounds','att_week_pick',
             'att_week_edition','att_hero_pick','att_archive_calibration','att_series_kind_of_node') loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. Cron (UTC): the archive driver every 2 minutes outside 05:40–08:50; weekly edition Monday 09:05 for the week just closed
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare j record; begin
  for j in select jobid from cron.job where jobname in ('att-archive-run','att-week-edition','att-wse-looks') loop perform cron.unschedule(j.jobid); end loop;
end $$;
select cron.schedule('att-archive-run', '1-59/2 * * * *', $$set statement_timeout = '30min'; select ripples.att_archive_step_locked()$$);
-- att-wse-looks (ops): the committed look stepper of §2b, every minute outside 05:40–08:50; unschedule once wse.looks_step is idle
-- and nothing reconstructed is pending (the archive driver then runs one event at a time through att_run_library).
select cron.schedule('att-wse-looks', '* * * * *', $$set statement_timeout = '4min'; select ripples.att_archive_looks_step(50)$$);
select cron.schedule('att-week-edition', '5 9 * * 1', $$set statement_timeout = '5min'; select ripples.att_week_edition(to_char(current_date - 7, 'IYYY-IW'))$$);
