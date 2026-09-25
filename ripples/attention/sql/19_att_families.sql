-- 19_att_families (v6 WS-A, 2026-09-25; applied as migration att_families_core)
-- ENGINE_SPEC §1.3 (families, calendar), §2.1 (mechanism library), §5.6.4 (positive controls), §5.7 (time split),
-- §5.8 (event library / reconstructed archive), §10.2 (att_families, att_family_calendar, att_family_events, att_controls).
--
-- 1. Mechanism library v6.0 <-> WS-B resolver. WS-B's att_resolve_targets (21_att_engine_freeze.sql) reads ONE target per
--    template: {"node"} | {"node_pattern","meta_key"} | {"source","keys_from":"topic_keys"}. The v6.0 templates keep their
--    full WS-A form (nodes[], pattern/patterns with {BA}/{ST}, sources[]/also[], topic_keys, demean/agg, geo_filter) for
--    att_build_graph, and att_family_sync() adds the primary WS-B key. Every other target of a template goes into the family
--    mapper (att_families.mapper, WS-B format, same template name), so each (family, target) is proposed exactly once.
--    MONEY templates are kept (channel inactive, D-10 decision pending) but never enter a mapper.
-- 2. WS-B's 8 placeholder templates (version '6.0', 21_att_engine_freeze.sql §3: "WS-A owns the full mappers and
--    overwrites with its own rows") are superseded by v6.0 templates and removed; no table references templates by FK.
-- 3. Geography for events: topic meta.state (2-letter codes) and meta.ba (first two EIA-930 BAs per state) are the
--    meta_key values WS-B's node_pattern items expand.
-- 4. Event library (role 'library', reconstructed = true): att_library_upsert() is the single writer (att-library edge
--    function + the SQL generators below). Topics: an existing topic with the same QID is reused untouched; otherwise a
--    dormant 'lib:<slug>' topic (dormant = never collected). in_prior_set = onset < 2026-01-01 (prior_cutoff),
--    in_replication_set = onset >= 2026-01-01; positive controls are in neither (ENGINE §5.7).
-- 5. Calendar: future CPI / jobs / FOMC dates from att_release_dates -> att_family_calendar, ledgered ('register') when new.
-- 6. Positive controls (ENGINE §5.6.4): 6 events (role positive_control) + fixtures in att_controls (kind 'positive') with
--    the expected target nodes; att_controls_baseline() checks >= 90 observed days before onset for every target.
-- Curated release dates (model / software releases, film and game premieres) are public dates written from general
-- knowledge on 2026-09-25, not fetched: meta.lib_source = 'curated-2026-09-25'; qid is left null until Wikidata can
-- verify them (the UA contact gate is closed), so none of them is presented as a verified identifier.

-- ------------------------------------------------------------------ 1-2. templates
delete from ripples.att_mech_templates
 where version = '6.0' and template in ('storm_fema_declaration','heat_henry_hub','cold_henry_hub','storm_transit_dip',
   'macro_rates','decision_prediction_market','model_release_packages','wildfire_air_quality');

-- aggregate key used by WS-B's att_engine_source_map (agg_key 'US48')
update ripples.att_mech_templates set target_pattern = jsonb_set(target_pattern, '{agg}', '"eia.930:US48"')
 where target_pattern->>'agg' = 'eia.930:US48SUM';

insert into ripples.att_mech_templates(template, family, target_pattern, sign, channel, l_days, rationale, version) values
 ('quake_felt_reports','hazard.quake','{"nodes":["usgs.eq:felt","usgs.eq:sig"]}',1,'PHYS',7,
  'Earthquake felt widely -> more felt-report events in the USGS feed that day and the next (aftershocks, reporting)','v6.0')
on conflict (template) do update set family = excluded.family, target_pattern = excluded.target_pattern, sign = excluded.sign,
  channel = excluded.channel, l_days = excluded.l_days, rationale = excluded.rationale, version = excluded.version;

create or replace function ripples.att_family_sync(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_t int; n_f int;
begin
  -- a. primary WS-B key per template (idempotent: previous primary keys are dropped first)
  update ripples.att_mech_templates t
     set target_pattern = (t.target_pattern - 'node' - 'node_pattern' - 'meta_key' - 'keys_from') || case
       when coalesce((t.target_pattern->>'topic_keys')::boolean, false)
            and coalesce(t.target_pattern->>'source', t.target_pattern->'sources'->>0) is not null
         then jsonb_build_object('source', coalesce(t.target_pattern->>'source', t.target_pattern->'sources'->>0), 'keys_from', 'topic_keys')
       when jsonb_array_length(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) > 0
         then jsonb_build_object('node', t.target_pattern->'nodes'->>0)
       when coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0) is not null
         then jsonb_build_object(
           'node_pattern', replace(replace(coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0), '{ST}', '{}'), '{BA}', '{}'),
           'meta_key', case when coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0) like '%{BA}%' then 'ba' else 'state' end)
       else '{}'::jsonb end
   where t.version = p_version;
  get diagnostics n_t = row_count;

  -- b. family mappers = every non-primary target of the family's templates (MONEY excluded)
  with t as (select * from ripples.att_mech_templates where version = p_version and channel <> 'MONEY'),
  pats as (
    select t.template, z.pat, z.i from t
    cross join lateral jsonb_array_elements_text(
      (case when t.target_pattern ? 'pattern' then jsonb_build_array(t.target_pattern->'pattern') else '[]'::jsonb end)
      || coalesce(t.target_pattern->'patterns', '[]'::jsonb)) with ordinality z(pat, i)),
  items as (
    select t.family, t.template, 1 ord, n.i,
           jsonb_strip_nulls(jsonb_build_object('node', n.node, 'sign', t.sign, 'template', t.template, 'geo_filter', t.target_pattern->'geo_filter')) item
      from t cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) with ordinality n(node, i)
     where n.node is distinct from t.target_pattern->>'node'
    union all
    select t.family, t.template, 2, p.i,
           jsonb_build_object('node_pattern', replace(replace(p.pat, '{ST}', '{}'), '{BA}', '{}'),
                              'meta_key', case when p.pat like '%{BA}%' then 'ba' else 'state' end, 'sign', t.sign, 'template', t.template)
      from t join pats p on p.template = t.template
     where replace(replace(p.pat, '{ST}', '{}'), '{BA}', '{}') is distinct from t.target_pattern->>'node_pattern'
    union all
    select t.family, t.template, 3, s.i,
           jsonb_build_object('source', s.src, 'keys_from', 'topic_keys', 'sign', t.sign, 'template', t.template)
      from t cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'sources', '[]'::jsonb) || coalesce(t.target_pattern->'also', '[]'::jsonb))
             with ordinality s(src, i)
     where coalesce((t.target_pattern->>'topic_keys')::boolean, false) and s.src is distinct from t.target_pattern->>'source')
  update ripples.att_families f
     set mapper = coalesce((select jsonb_agg(item order by ord, template, i) from items where items.family = f.family), '[]'::jsonb)
   where f.family not in ('person', 'other');
  get diagnostics n_f = row_count;
  return jsonb_build_object('templates', n_t, 'families', n_f,
    'mapper_items', (select sum(jsonb_array_length(mapper)) from ripples.att_families));
end $$;

-- ------------------------------------------------------------------ 3. geography helpers
create or replace function ripples.att_state_bas(p_states text[], p_per_state int default 2) returns text[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(distinct b order by b), '{}')
    from ripples.att_geo_nodes g cross join lateral unnest(g.bas[1:p_per_state]) b
   where substr(g.geo, 4) = any(p_states)
$$;

-- ------------------------------------------------------------------ 4. event library writer
create or replace function ripples.att_library_upsert(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_topic bigint; v_ev bigint; v_states text[]; v_meta jsonb; v_slug text; v_onset date; v_fam text; v_role text;
        v_qid text; v_label text; v_ins boolean; v_mag real; n_new int := 0; n_upd int := 0; n_top int := 0; n_skip int := 0;
        skipped jsonb := '[]'::jsonb; v_merge boolean;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_slug := lower(r->>'slug'); v_fam := r->>'family'; v_role := coalesce(r->>'role', 'library');
    v_qid := nullif(upper(r->>'qid'), ''); v_label := left(btrim(r->>'label'), 200); v_mag := (r->>'magnitude')::real;
    v_onset := case when r->>'onset' ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'onset')::date end;
    if v_slug is null or v_slug !~ '^[a-z0-9][a-z0-9._-]{2,120}$' or v_onset is null or coalesce(v_label, '') = ''
       or v_onset < date '2019-01-01' or v_onset >= current_date
       or not exists (select 1 from ripples.att_families f where f.family = v_fam) or v_role not in ('library', 'positive_control')
       or (v_qid is not null and v_qid !~ '^Q[0-9]+$') then
      n_skip := n_skip + 1;
      if jsonb_array_length(skipped) < 10 then skipped := skipped || jsonb_build_object('slug', v_slug, 'why', 'invalid'); end if;
      continue;
    end if;
    -- merge = true (att-library FEMA, one declaration year per run): states are unioned with the stored ones and the
    -- magnitude keeps the larger value, so an incident declared across a year boundary ends up whole
    v_merge := coalesce((r->>'merge')::boolean, false);
    select coalesce(array_agg(distinct upper(x) order by upper(x)) filter (where upper(x) ~ '^[A-Z]{2}$'), '{}') into v_states
      from (select jsonb_array_elements_text(coalesce(r->'states', '[]'::jsonb)) x
            union all
            select jsonb_array_elements_text(t.meta->'state') from ripples.att_topics t
             where v_merge and t.label_key = 'lib:' || v_slug and jsonb_typeof(t.meta->'state') = 'array') z;
    if v_merge then
      select greatest(v_mag, e.magnitude) into v_mag from ripples.att_events e where e.slug = 'lib-' || v_slug and e.magnitude is not null;
      v_mag := coalesce(v_mag, (r->>'magnitude')::real);
    end if;
    v_meta := jsonb_strip_nulls(jsonb_build_object('library', true, 'family', v_fam, 'lib_source', r->>'source', 'lib_ref', r->>'ref',
               'state', case when cardinality(v_states) > 0 then to_jsonb(v_states) end,
               'ba', case when cardinality(v_states) > 0 then to_jsonb(ripples.att_state_bas(v_states)) end));
    v_topic := null;
    if v_qid is not null then select topic_id into v_topic from ripples.att_topics where qid = v_qid limit 1; end if;
    if v_topic is null then
      select topic_id into v_topic from ripples.att_topics where label_key = 'lib:' || v_slug;
      if v_topic is null then
        insert into ripples.att_topics(qid, label_key, label, title_en, lang, category, status, in_panel, origin, meta)
        values (v_qid, 'lib:' || v_slug, v_label, null, 'en',
                coalesce(r->>'category', case when v_fam like 'hazard.%' then 'hazard' when v_fam like 'tech.%' then 'tech'
                  when v_fam like 'policy.%' then 'policy' when v_fam = 'media.game' then 'games' else 'film_tv' end),
                'dormant', false, 'manual', v_meta)
        on conflict do nothing returning topic_id into v_topic;
        if v_topic is not null then n_top := n_top + 1;
        else select topic_id into v_topic from ripples.att_topics where label_key = 'lib:' || v_slug limit 1; end if;
      else
        update ripples.att_topics set meta = meta || v_meta where topic_id = v_topic and coalesce((meta->>'library')::boolean, false);
      end if;
    end if;
    begin
      insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug, reconstructed, status)
      values (v_onset + 1, v_topic, v_qid, v_label, v_fam, v_role, v_onset, v_mag, false, 'lib-' || v_slug, true, 'ended')
      on conflict (slug) do update set label = excluded.label, family = excluded.family, onset = excluded.onset, as_of = excluded.as_of,
         magnitude = excluded.magnitude, topic_id = excluded.topic_id, qid = excluded.qid, role = excluded.role
      returning event_id, (xmax = 0) into v_ev, v_ins;
    exception when unique_violation then
      n_skip := n_skip + 1;
      if jsonb_array_length(skipped) < 10 then skipped := skipped || jsonb_build_object('slug', v_slug, 'why', 'as_of/topic/role taken'); end if;
      continue;
    end;
    if v_ins then n_new := n_new + 1; else n_upd := n_upd + 1; end if;
    insert into ripples.att_family_events(event_id, family, onset, magnitude, in_prior_set, in_replication_set)
    values (v_ev, v_fam, v_onset, v_mag, v_role = 'library' and v_onset < date '2026-01-01', v_role = 'library' and v_onset >= date '2026-01-01')
    on conflict (event_id) do update set family = excluded.family, onset = excluded.onset, magnitude = excluded.magnitude,
       in_prior_set = excluded.in_prior_set, in_replication_set = excluded.in_replication_set;
  end loop;
  return jsonb_build_object('new', n_new, 'updated', n_upd, 'topics_new', n_top, 'skipped', n_skip, 'skipped_sample', skipped);
end $$;

-- scheduled macro releases since 2023 (ENGINE §5.8): CPI, Employment Situation, FOMC decision days that have passed
create or replace function ripples.att_library_macro(p_from date default date '2023-01-01') returns jsonb
language sql security definer set search_path = '' as $$
  select ripples.att_library_upsert(coalesce(jsonb_agg(jsonb_build_object(
    'slug', 'macro-' || r.release || '-' || to_char(r.release_date, 'YYYY-MM-DD'),
    'label', case r.release when 'cpi' then 'CPI release' when 'jobs' then 'Employment Situation (jobs report)' else 'FOMC decision' end
             || ' ' || to_char(r.release_date, 'YYYY-MM-DD'),
    'family', 'policy.macro_release', 'onset', r.release_date, 'category', 'policy',
    'source', case r.release when 'fomc' then 'federalreserve.gov calendar' else 'FRED release ' || r.fred_release_id end, 'ref', r.release)
    order by r.release_date, r.release), '[]'::jsonb))
  from ripples.att_release_dates r
  where r.release in ('cpi', 'jobs', 'fomc') and r.release_date between p_from and current_date - 1
$$;

-- curated release / premiere dates (public dates, written 2026-09-25; unverified until Wikidata P577 can check them)
create or replace function ripples.att_library_curated() returns jsonb
language sql security definer set search_path = '' as $$
  select ripples.att_library_upsert(jsonb_agg(jsonb_build_object('slug', slug, 'label', label, 'family', family, 'onset', onset,
           'source', 'curated-2026-09-25') order by onset))
  from (values
    -- AI model releases since 2022
    ('model-stable-diffusion-2022','Stable Diffusion public release','tech.model_release','2022-08-22'),
    ('model-whisper-2022','OpenAI Whisper release','tech.model_release','2022-09-21'),
    ('model-gpt-4-2023','GPT-4 release','tech.model_release','2023-03-14'),
    ('model-claude-2-2023','Claude 2 release','tech.model_release','2023-07-11'),
    ('model-llama-2-2023','Llama 2 release','tech.model_release','2023-07-18'),
    ('model-mistral-7b-2023','Mistral 7B release','tech.model_release','2023-09-27'),
    ('model-gemini-1-2023','Gemini 1.0 announcement','tech.model_release','2023-12-06'),
    ('model-claude-3-2024','Claude 3 release','tech.model_release','2024-03-04'),
    ('model-gpt-4o-2024','GPT-4o release','tech.model_release','2024-05-13'),
    ('model-claude-3-5-sonnet-2024','Claude 3.5 Sonnet release','tech.model_release','2024-06-20'),
    ('model-llama-3-1-2024','Llama 3.1 release','tech.model_release','2024-07-23'),
    ('model-o1-preview-2024','OpenAI o1-preview release','tech.model_release','2024-09-12'),
    ('model-deepseek-v3-2024','DeepSeek-V3 release','tech.model_release','2024-12-26'),
    ('model-claude-3-7-sonnet-2025','Claude 3.7 Sonnet release','tech.model_release','2025-02-24'),
    ('model-gpt-4-5-2025','GPT-4.5 release','tech.model_release','2025-02-27'),
    ('model-gemini-2-5-pro-2025','Gemini 2.5 Pro release','tech.model_release','2025-03-25'),
    ('model-llama-4-2025','Llama 4 release','tech.model_release','2025-04-05'),
    ('model-claude-4-2025','Claude 4 release','tech.model_release','2025-05-22'),
    ('model-gpt-5-2025','GPT-5 release','tech.model_release','2025-08-07'),
    -- software releases since 2022
    ('sw-ios-16-2022','iOS 16 release','tech.software_release','2022-09-12'),
    ('sw-python-3-11-2022','Python 3.11 release','tech.software_release','2022-10-24'),
    ('sw-nextjs-13-2022','Next.js 13 release','tech.software_release','2022-10-25'),
    ('sw-typescript-5-0-2023','TypeScript 5.0 release','tech.software_release','2023-03-16'),
    ('sw-nodejs-20-2023','Node.js 20 release','tech.software_release','2023-04-18'),
    ('sw-bun-1-0-2023','Bun 1.0 release','tech.software_release','2023-09-08'),
    ('sw-ios-17-2023','iOS 17 release','tech.software_release','2023-09-18'),
    ('sw-python-3-12-2023','Python 3.12 release','tech.software_release','2023-10-02'),
    ('sw-nextjs-14-2023','Next.js 14 release','tech.software_release','2023-10-26'),
    ('sw-nodejs-22-2024','Node.js 22 release','tech.software_release','2024-04-24'),
    ('sw-ios-18-2024','iOS 18 release','tech.software_release','2024-09-16'),
    ('sw-python-3-13-2024','Python 3.13 release','tech.software_release','2024-10-07'),
    ('sw-deno-2-0-2024','Deno 2.0 release','tech.software_release','2024-10-09'),
    ('sw-nextjs-15-2024','Next.js 15 release','tech.software_release','2024-10-21'),
    ('sw-react-19-2024','React 19 release','tech.software_release','2024-12-05'),
    -- film premieres (U.S. wide release) since 2024
    ('film-dune-part-two-2024','Dune: Part Two','media.film','2024-03-01'),
    ('film-godzilla-x-kong-2024','Godzilla x Kong: The New Empire','media.film','2024-03-29'),
    ('film-inside-out-2-2024','Inside Out 2','media.film','2024-06-14'),
    ('film-twisters-2024','Twisters','media.film','2024-07-19'),
    ('film-deadpool-wolverine-2024','Deadpool & Wolverine','media.film','2024-07-26'),
    ('film-beetlejuice-beetlejuice-2024','Beetlejuice Beetlejuice','media.film','2024-09-06'),
    ('film-joker-folie-a-deux-2024','Joker: Folie a Deux','media.film','2024-10-04'),
    ('film-wicked-2024','Wicked','media.film','2024-11-22'),
    ('film-gladiator-ii-2024','Gladiator II','media.film','2024-11-22'),
    ('film-moana-2-2024','Moana 2','media.film','2024-11-27'),
    ('film-captain-america-bnw-2025','Captain America: Brave New World','media.film','2025-02-14'),
    ('film-minecraft-movie-2025','A Minecraft Movie','media.film','2025-04-04'),
    ('film-sinners-2025','Sinners','media.film','2025-04-18'),
    ('film-thunderbolts-2025','Thunderbolts*','media.film','2025-05-02'),
    ('film-lilo-stitch-2025','Lilo & Stitch (2025)','media.film','2025-05-23'),
    ('film-mi-final-reckoning-2025','Mission: Impossible - The Final Reckoning','media.film','2025-05-23'),
    ('film-httyd-2025','How to Train Your Dragon (2025)','media.film','2025-06-13'),
    ('film-jurassic-world-rebirth-2025','Jurassic World Rebirth','media.film','2025-07-02'),
    ('film-superman-2025','Superman (2025)','media.film','2025-07-11'),
    ('film-fantastic-four-2025','The Fantastic Four: First Steps','media.film','2025-07-25'),
    -- game releases since 2024
    ('game-palworld-2024','Palworld (early access)','media.game','2024-01-19'),
    ('game-helldivers-2-2024','Helldivers 2','media.game','2024-02-08'),
    ('game-balatro-2024','Balatro','media.game','2024-02-20'),
    ('game-elden-ring-sote-2024','Elden Ring: Shadow of the Erdtree','media.game','2024-06-21'),
    ('game-black-myth-wukong-2024','Black Myth: Wukong','media.game','2024-08-20'),
    ('game-astro-bot-2024','Astro Bot','media.game','2024-09-06'),
    ('game-space-marine-2-2024','Warhammer 40,000: Space Marine 2','media.game','2024-09-09'),
    ('game-sparking-zero-2024','Dragon Ball: Sparking! Zero','media.game','2024-10-11'),
    ('game-black-ops-6-2024','Call of Duty: Black Ops 6','media.game','2024-10-25'),
    ('game-kcd2-2025','Kingdom Come: Deliverance II','media.game','2025-02-04'),
    ('game-monster-hunter-wilds-2025','Monster Hunter Wilds','media.game','2025-02-28'),
    ('game-split-fiction-2025','Split Fiction','media.game','2025-03-06'),
    ('game-clair-obscur-2025','Clair Obscur: Expedition 33','media.game','2025-04-24'),
    ('game-silksong-2025','Hollow Knight: Silksong','media.game','2025-09-04')
  ) v(slug, label, family, onset)
$$;

-- NOAA-derived heat waves / cold snaps (hazard.heat / hazard.cold) from the GHCN-Daily station panel (att-econ noaa):
-- station-day hot = TMAX >= that station's calendar-month p95 (2019..2025) and >= 30 C; cold = TMAX <= month p05 and <= 5 C.
-- A station is "in a run" on day d when d belongs to >= 3 consecutive hot days (>= 2 cold days). An event is a maximal
-- stretch of days with >= 5 stations in a run (gaps <= 2 days merged); onset = first day, states = states of those
-- stations, magnitude = ln(peak number of stations). Runs only after the NOAA backfill is complete (onsets would move).
create or replace function ripples.att_library_noaa_extremes(p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  if not p_force and not coalesce((select (v->>'complete')::boolean from ripples.att_state where k = 'econ.bf.noaa.ghcnd'), false) then
    return jsonb_build_object('skipped', 'noaa backfill incomplete');
  end if;
  with x as (
    select s.key stn, substr(s.geo, 4) st, o.day, o.value tmax
      from ripples.att_series s join ripples.attention_obs o using (series_id)
     where s.source = 'noaa.ghcnd' and s.metric = 'temp' and o.day >= date '2019-01-01'),
  clim as (
    select stn, extract(month from day)::int m,
           percentile_cont(0.95) within group (order by tmax) p95, percentile_cont(0.05) within group (order by tmax) p05
      from x where day < date '2026-01-01' group by 1, 2 having count(*) >= 60),
  flag as (
    select x.stn, x.st, x.day,
           (x.tmax >= c.p95 and x.tmax >= 30) hot, (x.tmax <= c.p05 and x.tmax <= 5) cold
      from x join clim c on c.stn = x.stn and c.m = extract(month from x.day)::int),
  runs as (
    select kind, stn, st, day, grp from (
      select 'heat' kind, stn, st, day, day - (row_number() over (partition by stn order by day))::int grp from flag where hot
      union all
      select 'cold', stn, st, day, day - (row_number() over (partition by stn order by day))::int from flag where cold) z),
  runlen as (select kind, stn, st, grp, count(*) n from runs group by 1, 2, 3, 4),
  inrun as (
    select r.kind, r.day, r.stn, r.st from runs r join runlen l using (kind, stn, st, grp)
     where l.n >= case r.kind when 'heat' then 3 else 2 end),
  daily as (select kind, day, count(distinct stn) n, array_agg(distinct st) sts from inrun group by 1, 2 having count(distinct stn) >= 5),
  seq as (select *, case when day - lag(day) over (partition by kind order by day) <= 3 then 0 else 1 end brk from daily),
  ev as (select *, sum(brk) over (partition by kind order by day) eid from seq),
  agg as (
    select kind, eid, min(day) onset, max(day) last_day, max(n) peak,
           (select array_agg(distinct s order by s) from ev e2 cross join lateral unnest(e2.sts) s where e2.kind = ev.kind and e2.eid = ev.eid) states
      from ev group by kind, eid)
  select jsonb_agg(jsonb_build_object(
           'slug', kind || '-' || to_char(onset, 'YYYY-MM-DD'),
           'label', case kind when 'heat' then 'Heat wave' else 'Cold snap' end || ' ' || to_char(onset, 'YYYY-MM-DD') || ' (' || array_length(states, 1) || ' states)',
           'family', 'hazard.' || kind, 'onset', onset, 'states', to_jsonb(states), 'magnitude', round(ln(peak)::numeric, 3),
           'source', 'noaa.ghcnd station panel', 'ref', 'peak ' || peak || ' stations, through ' || last_day) order by onset)
    into v_rows from agg where onset < current_date - 3;
  return ripples.att_library_upsert(coalesce(v_rows, '[]'::jsonb));
end $$;

-- ------------------------------------------------------------------ 5. calendar (scheduled macro releases, registered before onset)
create or replace function ripples.att_calendar_refresh() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int; v_seq bigint; v_rows jsonb;
begin
  with c as (
    select 'policy.macro_release'::text family,
           case r.release when 'cpi' then 'CPI release' when 'jobs' then 'Employment Situation (jobs report)' else 'FOMC decision' end label,
           r.release_date d
      from ripples.att_release_dates r where r.release in ('cpi', 'jobs', 'fomc') and r.release_date >= current_date),
  ins as (
    insert into ripples.att_family_calendar(family, label, qid, scheduled_for)
    select c.family, c.label, null, c.d from c
     where not exists (select 1 from ripples.att_family_calendar x where x.family = c.family and x.label = c.label and x.scheduled_for = c.d)
    returning id, family, label, scheduled_for)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', id, 'family', family, 'label', label, 'scheduled_for', scheduled_for)
           order by scheduled_for, label), '[]'::jsonb)
    into n, v_rows from ins;
  if n > 0 then
    v_seq := ripples._att_ledger_append_wsa(current_date, 'register',
               jsonb_build_object('object', 'family_calendar', 'rows', n, 'first', v_rows->0->>'scheduled_for', 'last', v_rows->(n - 1)->>'scheduled_for'),
               encode(extensions.digest(v_rows::text, 'sha256'), 'hex'));
    update ripples.att_family_calendar set ledger_seq = v_seq where id in (select (x->>'id')::bigint from jsonb_array_elements(v_rows) x);
  end if;
  return jsonb_build_object('registered', n, 'ledger_seq', v_seq,
    'upcoming', (select count(*) from ripples.att_family_calendar where scheduled_for >= current_date));
end $$;

-- ------------------------------------------------------------------ 6. positive controls (ENGINE §5.6.4)
create or replace function ripples.att_controls_seed() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare lib jsonb; n int := 0; c record;
begin
  lib := ripples.att_library_upsert(jsonb_build_array(
    jsonb_build_object('slug','control-hurricane-helene-2024','label','Hurricane Helene (positive control)','family','hazard.storm',
      'onset','2024-09-26','states',jsonb_build_array('FL','GA','NC','SC','TN','VA'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-hurricane-milton-2024','label','Hurricane Milton (positive control)','family','hazard.storm',
      'onset','2024-10-07','states',jsonb_build_array('FL'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-chatgpt-launch-2022','label','ChatGPT launch (positive control)','family','tech.model_release',
      'onset','2022-11-30','role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-texas-heat-dome-2023','label','July 2023 Texas heat dome (positive control)','family','hazard.heat',
      'onset','2023-07-10','states',jsonb_build_array('TX'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-llama-3-2024','label','Llama 3 release (positive control)','family','tech.model_release',
      'onset','2024-04-18','role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-deepseek-r1-2025','label','DeepSeek-R1 release (positive control)','family','tech.model_release',
      'onset','2025-01-20','role','positive_control','source','ENGINE §5.6.4')));
  for c in select * from (values
    ('control-hurricane-helene-2024', '[{"node":"tsa.pax:checkpoint","sign":-1,"channel":"PHYS","template":"storm_air_travel"},
       {"node":"fema.decl:st:NC","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"fema.decl:st:FL","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"iem.warn:__total__","sign":1,"channel":"INST","template":"storm_nws_warnings"}]'),
    ('control-hurricane-milton-2024', '[{"node":"tsa.pax:checkpoint","sign":-1,"channel":"PHYS","template":"storm_air_travel"},
       {"node":"fema.decl:st:FL","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"iem.warn:__total__","sign":1,"channel":"INST","template":"storm_nws_warnings"}]'),
    ('control-chatgpt-launch-2022', '[{"node":"npm.dl:openai","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:chatgpt","sign":1,"channel":"SOC","template":"model_release_hn"}]'),
    ('control-texas-heat-dome-2023', '[{"node":"eia.930:ERCO","sign":1,"channel":"PHYS","template":"heat_grid_demand"}]'),
    ('control-llama-3-2024', '[{"node":"npm.dl:ollama","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:llama","sign":1,"channel":"SOC","template":"model_release_hn"}]'),
    ('control-deepseek-r1-2025', '[{"node":"npm.dl:ollama","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:deepseek","sign":1,"channel":"SOC","template":"model_release_hn"}]')) v(slug, expect)
  loop
    if not exists (select 1 from ripples.att_controls where kind = 'positive' and spec->>'slug' = c.slug) then
      insert into ripples.att_controls(kind, spec)
      select 'positive', jsonb_build_object('slug', c.slug, 'event_slug', 'lib-' || c.slug, 'event_id', e.event_id, 'label', e.label,
               'family', e.family, 'onset', e.onset, 'expect', c.expect::jsonb, 'must', 'Measured', 'source', 'ENGINE §5.6.4',
               'note', 'hf.trending and pypi.dl have no history before 2026 (snapshot / 180-day APIs): npm + HN stand in for model releases')
        from ripples.att_events e where e.slug = 'lib-' || c.slug;
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('events', lib, 'fixtures_new', n);
end $$;

-- baseline check: observed days of every expected target in [onset - 120, onset - 1] (acceptance: >= 90)
create or replace function ripples.att_controls_baseline() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('control', c.spec->>'slug', 'node', x->>'node', 'onset', c.spec->>'onset',
           'baseline_days', b.n, 'post_days', b.p, 'ok', coalesce(b.n, 0) >= 90) order by c.spec->>'onset', x->>'node'), '[]'::jsonb)
  from ripples.att_controls c
  cross join lateral jsonb_array_elements(c.spec->'expect') x
  left join lateral (
    select count(distinct o.day) filter (where o.day between (c.spec->>'onset')::date - 120 and (c.spec->>'onset')::date - 1) n,
           count(distinct o.day) filter (where o.day between (c.spec->>'onset')::date and (c.spec->>'onset')::date + 30) p
      from ripples.att_series s join ripples.attention_obs o using (series_id)
     where s.source = split_part(x->>'node', ':', 1) and s.key = substr(x->>'node', length(split_part(x->>'node', ':', 1)) + 2)
       and s.metric = case when s.source = 'eia.930' then 'demand' else s.metric end) b on true
  where c.kind = 'positive'
$$;

revoke all on function ripples.att_family_sync(text), ripples.att_state_bas(text[], int), ripples.att_library_upsert(jsonb),
  ripples.att_library_macro(date), ripples.att_library_curated(), ripples.att_library_noaa_extremes(boolean),
  ripples.att_calendar_refresh(), ripples.att_controls_seed(), ripples.att_controls_baseline()
  from public, anon, authenticated;

-- public wrappers for att-library (service_role only)
create or replace function public.att_library_upsert(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_library_upsert(p_rows) $$;
create or replace function public.att_series_first_day(p_source text, p_key text, p_metric text default null) returns date
language sql stable security definer set search_path = '' as $$
  select min(o.day) from ripples.att_series s join ripples.attention_obs o using (series_id)
   where s.source = p_source and s.key = p_key and (p_metric is null or s.metric = p_metric)
$$;
revoke all on function public.att_library_upsert(jsonb), public.att_series_first_day(text, text, text) from public, anon, authenticated;
grant execute on function public.att_library_upsert(jsonb), public.att_series_first_day(text, text, text) to service_role;

-- ------------------------------------------------------------------ run once
select ripples.att_family_sync('v6.0');
select ripples.att_library_macro();
select ripples.att_library_curated();
select ripples.att_controls_seed();
select ripples.att_calendar_refresh();
select ripples.att_build_graph('v6.0');

-- ------------------------------------------------------------------ crons (UTC)
-- 05:40 graph rebuild (+ family sync), 05:20 Mon calendar + macro library (after att-econ-calendar 05:05 Mon),
-- 06:10 Sun NOAA extremes (no-op until the NOAA backfill is complete)
select cron.schedule('att-graph', '40 5 * * *', $$select ripples.att_family_sync('v6.0'); select ripples.att_build_graph('v6.0')$$);
select cron.schedule('att-calendar', '20 5 * * 1', $$select ripples.att_calendar_refresh(); select ripples.att_library_macro()$$);
select cron.schedule('att-lib-noaa', '10 6 * * 0', $$select ripples.att_library_noaa_extremes()$$);

-- =====================================================================================================================
-- Addendum (migration att_wsa_functions, 2026-09-25 ~19:40 UTC): support for the new WS-A edge functions
-- (att-library, att-wikidata, att-market-backfill, att-equities) and the engine source map for WS-A sources.
-- * att_market_bf_targets(source): topic-linked Kalshi events ('ev:<event>' vol24h series with a topic) and Polymarket
--   price series ('p') for att-market-backfill.
-- * wikidata.entity now uses the documented Action API (wbgetentities, 50 ids per call, maxlag=5; robots exemption of
--   DEMARCATION §7.1 applies to /w/api.php only). Special:EntityData is not requested.
-- * att_engine_source_map (WS-B table): rows for noaa.ghcnd and census.bfs (WS-A sources that had none) and per-metric
--   value kinds for sources whose metric names ARE the kind (fred: rate|level|count; noaa temp can be negative -> rate,
--   prcp -> count; equities store robust z -> rate). Inserted / updated only where WS-B left the default; WS-B to confirm.
-- * att_config 'equities' written with the collector defaults so the owner can edit the watch list without a deploy.
create or replace function public.att_market_bf_targets(p_source text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'metric', s.metric, 'topic_id', s.topic_id,
           'first_day', (select min(o.day) from ripples.attention_obs o where o.series_id = s.series_id),
           'created', s.created_at::date) order by s.key), '[]'::jsonb)
  from ripples.att_series s
  where s.source = p_source and s.topic_id is not null
    and ((p_source = 'kalshi.mkt' and s.key like 'ev:%' and s.metric = 'vol24h') or (p_source = 'poly.mkt' and s.metric = 'p'))
$$;
revoke all on function public.att_market_bf_targets(text) from public, anon, authenticated;
grant execute on function public.att_market_bf_targets(text) to service_role;

update ripples.att_sources set reason = 'Wikidata Action API wbgetentities (documented API; up to 50 ids per call, props labels|claims|sitelinks, en only, maxlag=5, serial >= 1.1 s; Api-User-Agent with contact; robots exemption for /w/api.php per DEMARCATION §7.1). Shared bucket wikidata (<= 550 calls/day). Whitelisted claims only (att_wd_props) -> graph edges, no observations. Blocked by the Wikimedia contact gate while the UA contact page is unreachable'
 where source = 'wikidata.entity';

insert into ripples.att_engine_source_map(source, channel, value_kind, same_dow, agg_key, domain, metric_kinds) values
  ('noaa.ghcnd', 'PHYS', 'rate', false, null, 'real_world', '{"temp":"rate","prcp":"count"}'),
  ('census.bfs', 'ECON', 'count', false, 'US', 'economy', '{"ba":"count"}')
on conflict (source) do nothing;
update ripples.att_engine_source_map set metric_kinds = '{"rate":"rate","level":"level","count":"count"}'
 where source = 'fred' and metric_kinds = '{}'::jsonb;
update ripples.att_engine_source_map set metric_kinds = '{"volz":"rate","retz":"rate"}'
 where source in ('twelvedata', 'alphavantage') and metric_kinds = '{}'::jsonb;

insert into ripples.att_config(key, value) values ('equities', jsonb_build_object(
  'etfs', jsonb_build_array('SPY','XLE','XLU','XLK','SMH','XHB','XRT','JETS','ITB','KRE','XLF','XLV','XLI','XLB','XLP','XLY','XLC',
          'XLRE','IYT','XOP','KIE','IGV','XME','PEJ','ICLN','TAN','USO','UNG','CIBR','IBB'),
  'td_max_symbols', 60, 'td_daily_outputsize', 160, 'bf_from', '2018-06-01',
  'av_symbols', jsonb_build_array('XLE','XLU','SMH','JETS','KRE','XRT'), 'recent_days', 10,
  'note', 'D-10: derived z only (volz, retz); raw bars never stored. MONEY channel inactive until the lead decides (ENGINE §8)'))
on conflict (key) do nothing;

-- =====================================================================================================================
-- Addendum (migration att_wsa_crons, 2026-09-25 ~20:00 UTC): schedules for the new WS-A functions (UTC).
-- Backfill drains stop by themselves (SQL guard on their att_state cursor); every request is still bounded by the
-- source's per-run cap and per-day budget inside politeFetch.
-- * twelvedata: api.twelvedata.com/robots.txt answered "Disallow: /" on 2026-09-25 -> robots honoured, no request made;
--   the source is disabled (reason recorded) and NOT scheduled until an owner/lead decision (same class as api.bls.gov).
-- * alphavantage: per-run cap 7 (SPY + 6 ETFs = one daily run; per-day cap 12 unchanged).
update ripples.att_sources set enabled = false,
  reason = 'Disabled 2026-09-25: api.twelvedata.com/robots.txt is "User-agent: * / Disallow: /" -> robots honoured (hard rule), no request made. Keyed documented API, owner key in Vault (twelvedata_api_key). Re-enable only with an owner/lead decision recorded in DEMARCATION (API-robots exemption like Wikimedia §7.1) and an att.ts override'
 where source = 'twelvedata';
update ripples.att_sources set per_run_cap = 7 where source = 'alphavantage';
select ripples.att_fn_live('att-library'); select ripples.att_fn_live('att-wikidata');
select ripples.att_fn_live('att-market-backfill'); select ripples.att_fn_live('att-equities');

select cron.schedule('att-lib-fema-bf', '3-59/7 * * * *', $$
  select public.call_collector('att-library', '{"mode":"fema"}'::jsonb)
   where not coalesce((select (v->>'done')::boolean from ripples.att_state where k = 'lib.fema'), false) $$);
select cron.schedule('att-lib-fema', '35 7 * * *', $$select public.call_collector('att-library', '{"mode":"fema","params":{"daily":true}}'::jsonb)$$);
select cron.schedule('att-lib-usgs-bf', '5-59/9 * * * *', $$
  select public.call_collector('att-library', '{"mode":"usgs"}'::jsonb)
   where coalesce((select (v->>'next')::int from ripples.att_state where k = 'lib.usgs'), 2019) <= extract(year from now())::int $$);
select cron.schedule('att-lib-usgs', '40 7 * * *', $$select public.call_collector('att-library', '{"mode":"usgs","params":{"daily":true}}'::jsonb)$$);
select cron.schedule('att-lib-gdacs-bf', '7-59/11 * * * *', $$
  select public.call_collector('att-library', '{"mode":"gdacs"}'::jsonb)
   where coalesce((select (v->>'next')::int from ripples.att_state where k = 'lib.gdacs'), 2019) <= extract(year from now())::int $$);
select cron.schedule('att-lib-gdacs', '45 7 * * 1', $$select public.call_collector('att-library', '{"mode":"gdacs","params":{"daily":true}}'::jsonb)$$);
select cron.schedule('att-lib-iem-bf', '2-59/5 * * * *', $$
  select public.call_collector('att-library', '{"mode":"iem_bf"}'::jsonb)
   where not coalesce((select (v->>'done')::boolean from ripples.att_state where k = 'lib.bf.iem'), false) $$);
select cron.schedule('att-lib-npm-bf', '4-59/10 * * * *', $$
  select public.call_collector('att-library', '{"mode":"npm_bf"}'::jsonb)
   where coalesce((select count(*) filter (where value #>> '{}' <= '2022-06-01') from ripples.att_state s, jsonb_each(s.v)
                    where s.k = 'lib.bf.npm'), 0) < 5 $$);
select cron.schedule('att-lib-hn-bf', '6-59/10 * * * *', $$
  select public.call_collector('att-library', '{"mode":"hn_bf"}'::jsonb)
   where coalesce((select count(*) filter (where (value->>'complete')::boolean) from ripples.att_state s, jsonb_each(s.v)
                    where s.k = 'lib.bf.hn'), 0) < 6 $$);
select cron.schedule('att-wikidata', '17 * * * *', $$select public.call_collector('att-wikidata', '{"mode":"claims","params":{"limit":250}}'::jsonb)$$);
select cron.schedule('att-mbf-kalshi', '25 8,20 * * *', $$select public.call_collector('att-market-backfill', '{"mode":"kalshi"}'::jsonb)$$);
select cron.schedule('att-mbf-poly', '35 9 * * 0', $$select public.call_collector('att-market-backfill', '{"mode":"poly_deep"}'::jsonb)$$);
select cron.schedule('att-eq-av', '5 23 * * 1-5', $$select public.call_collector('att-equities', '{"mode":"alphavantage"}'::jsonb)$$);

-- =====================================================================================================================
-- Addendum (migration att_market_hist_sources, 2026-09-25 ~20:10 UTC): fetch-only sources for att-market-backfill.
-- The first live runs found kalshi.mkt and poly.mkt daily budgets already spent by att-market's crawl, so the price
-- backfill gets its own small budgets on the same hosts (the host lease still serialises it with att-market). No series
-- are stored under these ids (rows go to kalshi.mkt / poly.mkt).
insert into ripples.att_sources(source, family, channel, grain, value_kind, tier, grade, quality, enabled, policy_d1, hosts,
  per_run_cap, per_day_cap, spacing_ms, budget_bucket, robots_required, needs_secret, attribution, license_note, reason, engine_channel)
values
 ('kalshi.hist', 'kalshi', 'money', 'day', 'rate', 'ship', 'yellow', 1, true, false, array['api.elections.kalshi.com'],
  40, 80, 250, null, true, null, 'Kalshi', 'Ask Kalshi about market-data licensing',
  'Fetch-only (att-market-backfill): event markets + daily candlesticks for topic-linked events; prices stored as kalshi.mkt metric p. Own budget 80/day so att-market''s crawl budget is untouched. Q6: 20 reads/s basic tier -> 4/s', 'PM'),
 ('poly.hist', 'polymarket', 'money', 'day', 'rate', 'ship', 'yellow', 1, true, false, array['gamma-api.polymarket.com','clob.polymarket.com'],
  40, 60, 500, null, true, null, 'Polymarket', null,
  'Fetch-only (att-market-backfill poly_deep): full CLOB daily price history for price series cut at att-market''s 400-day window; stored as poly.mkt metric p. Own budget 60/day', 'PM')
on conflict (source) do update set hosts = excluded.hosts, per_run_cap = excluded.per_run_cap, per_day_cap = excluded.per_day_cap,
  spacing_ms = excluded.spacing_ms, reason = excluded.reason, enabled = excluded.enabled, engine_channel = excluded.engine_channel;

-- =====================================================================================================================
-- Addendum (migration att_econ_cron_fix, 2026-09-25 ~20:20 UTC)
-- * FRED has no PRICLAIMS series (400 "series does not exist"): the FRED backfill drain stops at 77 fetched series
--   (it would otherwise spend one request every 6 minutes on it). The daily fred mode still asks for it once a day
--   (1 request, reported as an error) until att-econ drops PR from its FRED list (follow-up).
-- * Census BFS weekly business applications: weekly refresh on Thursdays after the 10:00 ET release.
select cron.alter_job((select jobid from cron.job where jobname = 'att-econ-bf-fred'), command := $$
  select public.call_collector('att-econ', '{"mode":"backfill","params":{"source":"fred"}}'::jsonb)
   where coalesce((select count(*) from jsonb_object_keys(coalesce((select v from ripples.att_state where k = 'econ.fred.fetched'), '{}'::jsonb))), 0) < 77 $$);
select cron.schedule('att-econ-bfs', '25 15 * * 4', $$select public.call_collector('att-econ', '{"mode":"census_bfs"}'::jsonb)$$);

-- =====================================================================================================================
-- Addendum (migration att_controls_merge, 2026-09-25 ~20:30 UTC): WS-B had already written its own positive-control
-- specs into att_controls (ids 7-12: {name, label, onset, family, any_of, expect: [node, ...]}). To avoid two fixture
-- sets, WS-A's rows are merged into WS-B's: each WS-B row gains event_slug / event_id (the reconstructed
-- positive_control event in att_events) and wsa_expect (WS-A's signed, channel-tagged targets); WS-A's own rows are
-- removed. att_controls_baseline() reads both node lists (expect as strings or objects, and wsa_expect).
create or replace function ripples.att_controls_seed() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare lib jsonb; n_merged int := 0; n_new int := 0; c record; v_id bigint;
begin
  lib := ripples.att_library_upsert(jsonb_build_array(
    jsonb_build_object('slug','control-hurricane-helene-2024','label','Hurricane Helene (positive control)','family','hazard.storm',
      'onset','2024-09-26','states',jsonb_build_array('FL','GA','NC','SC','TN','VA'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-hurricane-milton-2024','label','Hurricane Milton (positive control)','family','hazard.storm',
      'onset','2024-10-07','states',jsonb_build_array('FL'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-chatgpt-launch-2022','label','ChatGPT launch (positive control)','family','tech.model_release',
      'onset','2022-11-30','role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-texas-heat-dome-2023','label','July 2023 Texas heat dome (positive control)','family','hazard.heat',
      'onset','2023-07-10','states',jsonb_build_array('TX'),'role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-llama-3-2024','label','Llama 3 release (positive control)','family','tech.model_release',
      'onset','2024-04-18','role','positive_control','source','ENGINE §5.6.4'),
    jsonb_build_object('slug','control-deepseek-r1-2025','label','DeepSeek-R1 release (positive control)','family','tech.model_release',
      'onset','2025-01-20','role','positive_control','source','ENGINE §5.6.4')));
  for c in select v.slug, v.expect::jsonb expect, e.event_id, e.onset, e.family from (values
    ('control-hurricane-helene-2024', '[{"node":"tsa.pax:checkpoint","sign":-1,"channel":"PHYS","template":"storm_air_travel"},
       {"node":"fema.decl:st:NC","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"fema.decl:st:FL","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"iem.warn:__total__","sign":1,"channel":"INST","template":"storm_nws_warnings"}]'),
    ('control-hurricane-milton-2024', '[{"node":"tsa.pax:checkpoint","sign":-1,"channel":"PHYS","template":"storm_air_travel"},
       {"node":"fema.decl:st:FL","sign":1,"channel":"INST","template":"storm_fema_decl"},
       {"node":"iem.warn:__total__","sign":1,"channel":"INST","template":"storm_nws_warnings"}]'),
    ('control-chatgpt-launch-2022', '[{"node":"npm.dl:openai","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:chatgpt","sign":1,"channel":"SOC","template":"model_release_hn"}]'),
    ('control-texas-heat-dome-2023', '[{"node":"eia.930:ERCO","sign":1,"channel":"PHYS","template":"heat_grid_demand"}]'),
    ('control-llama-3-2024', '[{"node":"npm.dl:ollama","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:llama","sign":1,"channel":"SOC","template":"model_release_hn"}]'),
    ('control-deepseek-r1-2025', '[{"node":"npm.dl:ollama","sign":1,"channel":"BLD","template":"model_release_npm"},
       {"node":"hn.algolia:deepseek","sign":1,"channel":"SOC","template":"model_release_hn"}]')) v(slug, expect)
    join ripples.att_events e on e.slug = 'lib-' || v.slug
  loop
    select id into v_id from ripples.att_controls
     where kind = 'positive' and spec->>'onset' = c.onset::text and coalesce(spec->>'family', c.family) = c.family
       and spec->>'slug' is null order by id limit 1;
    if v_id is not null then
      update ripples.att_controls set spec = spec || jsonb_build_object('event_slug', 'lib-' || c.slug, 'event_id', c.event_id,
        'wsa_expect', c.expect, 'wsa_note', 'hf.trending and pypi.dl keep no history before 2026 (snapshot / 180-day APIs); npm + HN are backfilled by att-library')
       where id = v_id;
      n_merged := n_merged + 1;
    elsif not exists (select 1 from ripples.att_controls where kind = 'positive' and spec->>'event_slug' = 'lib-' || c.slug) then
      insert into ripples.att_controls(kind, spec) values ('positive', jsonb_build_object('slug', c.slug, 'event_slug', 'lib-' || c.slug,
        'event_id', c.event_id, 'onset', c.onset, 'family', c.family, 'expect', c.expect, 'must', 'Measured', 'source', 'ENGINE §5.6.4'));
      n_new := n_new + 1;
    end if;
  end loop;
  delete from ripples.att_controls a where a.kind = 'positive' and a.spec ? 'slug' and a.spec->>'slug' like 'control-%'
    and exists (select 1 from ripples.att_controls b where b.id <> a.id and b.spec->>'event_slug' = 'lib-' || (a.spec->>'slug') and not b.spec ? 'slug');
  return jsonb_build_object('events', lib, 'merged_into_wsb', n_merged, 'new', n_new);
end $$;

create or replace function ripples.att_controls_baseline() returns jsonb
language sql stable security definer set search_path = '' as $$
  with nodes as (
    select c.id, coalesce(c.spec->>'name', c.spec->>'slug') control, (c.spec->>'onset')::date onset, n.node, n.src
      from ripples.att_controls c
      cross join lateral (
        select coalesce(x->>'node', x #>> '{}') node, 'expect' src from jsonb_array_elements(coalesce(c.spec->'expect', '[]'::jsonb)) x
        union
        select x->>'node', 'wsa_expect' from jsonb_array_elements(coalesce(c.spec->'wsa_expect', '[]'::jsonb)) x) n
     where c.kind = 'positive')
  select coalesce(jsonb_agg(jsonb_build_object('control', control, 'node', node, 'list', src, 'onset', onset,
           'baseline_days', b.n, 'post_days', b.p, 'ok', coalesce(b.n, 0) >= 90) order by onset, control, node), '[]'::jsonb)
  from nodes
  left join lateral (
    select count(distinct o.day) filter (where o.day between nodes.onset - 120 and nodes.onset - 1) n,
           count(distinct o.day) filter (where o.day between nodes.onset and nodes.onset + 30) p
      from ripples.att_series s join ripples.attention_obs o using (series_id)
     where s.source = split_part(nodes.node, ':', 1) and s.key = substr(nodes.node, length(split_part(nodes.node, ':', 1)) + 2)
       and s.metric = case when s.source = 'eia.930' then 'demand' else s.metric end) b on true
$$;
select ripples.att_controls_seed();
