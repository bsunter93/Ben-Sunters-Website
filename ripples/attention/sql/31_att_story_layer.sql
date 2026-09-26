-- Ripple Map — STORY LAYER (presentation selection above an immutable evidence floor). OWNER_DECISIONS D-14, D-15 (UX_V2_OWNER_FEEDBACK).
-- Story editor, 2026-09-26. Additive objects only: nothing in 20–30 (engine) or 06_rm_public_rpcs is modified.
--
-- Funnel: Discovery (permissive) → Evidence (engine 6.1/6.2 + BigQuery gate; decides what may be SAID) → Story selection (this file;
-- decides what is SHOWN FIRST, aggressively, among survivors) → Presentation (frontend).
--
-- Hard rules (asserted by ripples.att_test_story(), T30–T37 in test_engine.sql):
--   * story fields NEVER alter an evidence tier: `engine_tier` is read from the engine's cascade payload, `tier` from att_ce_gate
--     (the forecast gate) — the same two reads rm_cascade_content makes. att_story_score is a pure function of story fields only.
--   * a graph edge is 'chain' (event → A → B) ONLY when the engine's fork/mediation checks support A → B
--     (att_hop_tests.detail -> 'chain': fork_test = false AND mediation_c = true, fork_of null); otherwise it is 'fork' (event → A, event → B).
--   * Likely / Watching stories never carry Measured wording; a gate-demoted hop is always shown at its demoted tier with the gate's reason.
--   * Ghost / Collapse ("Non-Event") stories exist only for pre-registered expected effects (att_hop_registry.p_hat > 0) whose window
--     closed and whose final engine verdict is flat.
--   * low coherence (temporal < 0.5 or mechanism < 0.4, or an unnamed node) → never featured, whatever the score.
--
-- Objects: ripples.att_story_candidates (table, refreshed daily by pg_cron in ≤ 100 s chunks), ripples.att_story_featured (novelty log),
-- att_config 'story' (weights, documented), pure helpers att_story_*, refresh att_story_refresh(p_budget_s), public.rm_stories(p_limit, p_days, p_kind)
-- (anon read; leak guard via rm_label_resolve / rm_node_hidden / rm_label_leaks; no raw ids in public text), ripples.rm_story_contract_test()
-- (fixture ripples/contract/fixtures/v2/stories.json — a separate RPC because rm_shape_diff reports extra keys on the existing payloads).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables + config
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_story_candidates (
  story_id        text primary key,                  -- 'cascade:{event}:{root_hop}' | 'watching:{event}:{hop}' | 'non_event:{event}:{hop}' | 'ghost:{event}' | 'pattern:{grid}'
  story_kind      text not null check (story_kind in ('cascade','watching','non_event','pattern')),
  event_id        bigint,                            -- null for patterns
  grid_id         int,                               -- 6.2 pair for patterns (and the matched pair for cascade replication)
  root_hop        bigint,
  hop_ids         bigint[] not null default '{}',    -- the evidence graph (root + subtree), engine hop ids
  engine_tier     text,                              -- root's tier as the engine published it (att_cascades payload) — READ-ONLY
  tier            text,                              -- root's public tier after the forecast gate (att_ce_gate) — READ-ONLY
  gate            jsonb,                             -- {demoted, reason, engine_tier}
  tier_min        text, tier_max text,               -- over the graph
  fields          jsonb not null,                    -- every story field (see att_story_fields_doc())
  graph           jsonb not null,                    -- {nodes:[{hop_id,depth,domain,tier,...}], edges:[{from,to,kind:'chain'|'fork'}]}
  archetype       text,                              -- presentation label only
  archetypes      text[] not null default '{}',
  hero_stop       bigint,
  spine           bigint[] not null default '{}',
  branches        bigint[] not null default '{}',
  story_score     real,
  coherence_score real,
  featurable      boolean not null default false,
  exclude_reason  text,
  watching        jsonb,                             -- {window_close, next_look, days_to_resolve, p_hat, expected_1_in}
  replication     jsonb,                             -- {n_similar, n_seen, n_strict, example_event_ids, strength, effect_pct, grid_id, regional:{...}}
  sensitivity     jsonb,                             -- {quiet, family, is_control}
  copy            jsonb,                             -- D-16: {story_sentence, short_title, conversation_hook, share_line} (tier-honest templates; null when a node has no public name)
  travel          jsonb,                             -- D-16: {domains_crossed, days, depth}
  first_seen      timestamptz not null default now(),-- share identity: when this story first existed (kept across refreshes)
  refreshed_at    timestamptz not null default now()
);
alter table ripples.att_story_candidates add column if not exists copy jsonb, add column if not exists travel jsonb,
  add column if not exists first_seen timestamptz not null default now();
create index if not exists att_story_candidates_event_idx on ripples.att_story_candidates (event_id);
create index if not exists att_story_candidates_feat_idx on ripples.att_story_candidates (featurable, story_score desc);
create table if not exists ripples.att_story_featured (   -- what the home list showed, for novelty (14-day memory)
  day date not null, story_id text not null, rank int not null, family text, domain text, event_id bigint, primary key (day, story_id));
alter table ripples.att_story_candidates enable row level security;
alter table ripples.att_story_featured   enable row level security;
revoke all on ripples.att_story_candidates, ripples.att_story_featured from anon, authenticated, public;

-- Weights (documented; owner-tunable). Score = Σ w·field − penalties; every field is 0..1. Changing weights changes ORDER only.
insert into ripples.att_config (key, value) values ('story', jsonb_build_object(
  'version', '1.0',
  'weights', jsonb_build_object(
    'temporal_coherence', 0.13, 'mechanism_coherence', 0.13, 'evidence_at_transitions', 0.18, 'domain_diversity', 0.08,
    'surprise', 0.08, 'counterintuitiveness', 0.12, 'magnitude', 0.08, 'replication', 0.08, 'independent_confirmations', 0.05, 'visual_clarity', 0.04, 'novelty', 0.03),
  -- D-16: counterintuitive findings are favoured disproportionately; unsurprising strong links (hurricane → FEMA) stay available but not hero
  'penalties', jsonb_build_object('common_cause_risk', 0.10, 'length_per_hop', 0.04, 'branching_noise', 0.05, 'unsurprising', 0.10),
  'gates', jsonb_build_object('temporal_min', 0.5, 'mechanism_min', 0.4, 'novelty_days', 14, 'ghost_min_expected', 3, 'collapse_min_p_hat', 0.15, 'unsurprising_below', 0.3),
  'scales', jsonb_build_object('effect_full_scale_logpts', 0.25, 'points_full_scale', 1.0, 'diversity_full_at', 3),
  'off_limits_regex', '\m(killed|killing|murder|shooting|massacre|suicide|stabbing|victims?|died|death of|dies|funeral|obituary|rape|assault)\M',
  'off_limits_families', '[]'::jsonb,
  'sensitivity_note', 'quiet = quiet presentation only; off_limits = the only exclusion (deaths / violence involving individuals)',
  'note', 'story_score orders survivors; it can never change p, q, tier, attribution or wording. Coherence gates exclude regardless of score.'))
on conflict (key) do nothing;
update ripples.att_config set value = value || jsonb_build_object('off_limits_regex', '\m(killed|killing|murder|shooting|massacre|suicide|stabbing|victims?|died|death of|dies|funeral|obituary|rape|assault)\M', 'off_limits_families', '[]'::jsonb,
  'sensitivity_note', 'quiet = quiet presentation only; off_limits = the only exclusion (deaths / violence involving individuals)') where key = 'story' and not value ? 'off_limits_regex';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Pure helpers (no table reads unless stated)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_story_tier_score(p_tier text, p_provisional boolean default false) returns real
language sql immutable set search_path = '' as $$
  select case p_tier when 'measured' then 1.0 when 'likely' then case when p_provisional then 0.5 else 0.6 end when 'watching' then 0.2 else 0.0 end::real
$$;
-- edge kind from the engine's chaining record (ENGINE §4.3–4.4). NO record → 'fork'. This is the hard rule.
create or replace function ripples.att_story_edge_kind(p_chain jsonb, p_fork_of jsonb) returns text
language sql immutable set search_path = '' as $$
  select case when p_chain is not null and jsonb_typeof(p_chain) = 'object'
                   and coalesce((p_chain ->> 'fork_test')::boolean, true) = false
                   and coalesce((p_chain ->> 'mediation_c')::boolean, false) = true
                   and (p_fork_of is null or jsonb_typeof(p_fork_of) = 'null')
              then 'chain' else 'fork' end
$$;
-- public tier from the engine tier and the forecast gate's answer (the gate only ever demotes a 'measured')
create or replace function ripples.att_story_public_tier(p_engine_tier text, p_gate jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_engine_tier = 'measured' and coalesce(p_gate ->> 'tier', 'measured') <> 'measured'
              then jsonb_build_object('tier', p_gate ->> 'tier', 'demoted', true, 'reason', p_gate ->> 'reason', 'engine_tier', 'measured')
              else jsonb_build_object('tier', p_engine_tier, 'demoted', false, 'reason', null, 'engine_tier', p_engine_tier) end
$$;
-- mechanism support of one frozen path (ENGINE §2.1 path types): min over its edges; a negative-control path has none
create or replace function ripples.att_story_mech_support(p_path jsonb) returns real
language sql immutable set search_path = '' as $$
  select coalesce((select min(case when e ->> 'source' = 'negative control' then 0.0
                                   when e ->> 'type' in ('MAP','MECH') then 1.0 when e ->> 'type' = 'WD' then 0.7
                                   when e ->> 'type' in ('CS','GK') then 0.5 when e ->> 'type' = 'WIKI' then 0.4 else 0.0 end)
                     from jsonb_array_elements(case when jsonb_typeof(p_path) = 'array' then p_path else '[]'::jsonb end) e), 0.0)::real
$$;
-- lag plausibility against the template / channel window L (days): unknown 0.5, negative 0, ≤ L 1, ≤ 2L 0.6, else 0.3
create or replace function ripples.att_story_lag_plaus(p_lag float8, p_l int) returns real
language sql immutable set search_path = '' as $$
  select case when p_lag is null then 0.5 when p_lag < 0 then 0.0 when p_l is null then 0.7
              when p_lag <= p_l then 1.0 when p_lag <= 2 * p_l then 0.6 else 0.3 end::real
$$;
-- normalised effect 0..1 on a common scale (log points / full scale; 'points' units: |rho| / points_full_scale)
create or replace function ripples.att_story_effect_norm(p_rho float8, p_unit text, p_scales jsonb default null) returns real
language sql immutable set search_path = '' as $$
  select case when p_rho is null then null
              when p_unit = 'points' then least(1, abs(p_rho) / coalesce((p_scales ->> 'points_full_scale')::float8, 1.0))
              when p_rho <= 0 then 1
              else least(1, abs(ln(p_rho)) / coalesce((p_scales ->> 'effect_full_scale_logpts')::float8, 0.25)) end::real
$$;
-- the score: Σ weights·fields − penalties, clamped to [0,1]. Pure. Fields missing → 0.
create or replace function ripples.att_story_score(p_fields jsonb, p_cfg jsonb) returns real
language sql immutable set search_path = '' as $$
  with w as (select k, (v #>> '{}')::float8 wt from jsonb_each(coalesce(p_cfg -> 'weights', '{}'::jsonb)) x(k, v)),
       s as (select coalesce(sum(w.wt * least(1, greatest(0, coalesce((p_fields ->> w.k)::float8, 0)))), 0) v from w)
  select least(1, greatest(0, s.v
           - coalesce((p_cfg -> 'penalties' ->> 'common_cause_risk')::float8, 0) * coalesce((p_fields ->> 'common_cause_risk')::float8, 0)
           - coalesce((p_cfg -> 'penalties' ->> 'length_per_hop')::float8, 0) * greatest(0, coalesce((p_fields ->> 'length')::float8, 1) - 1)
           - coalesce((p_cfg -> 'penalties' ->> 'branching_noise')::float8, 0) * coalesce((p_fields ->> 'branching_noise')::float8, 0)
           - case when coalesce((p_fields ->> 'counterintuitiveness')::float8, 1) < coalesce((p_cfg -> 'gates' ->> 'unsurprising_below')::float8, 0.3)
                  then coalesce((p_cfg -> 'penalties' ->> 'unsurprising')::float8, 0) else 0 end))::real
  from s
$$;
-- D-16 story copy: the "aha sentence", short title, conversation hook and share line. Deterministic templates from story fields; tier-honest verbs
-- (Measured: "showed up in"; Likely: "may have shown up in" / "consistent with"; Watching: "might be showing up in"; dead end: "never showed up in").
-- Never a causal verb. Pure.
create or replace function ripples.att_story_copy(p_kind text, p_archetype text, p_tier text, p_event_label text, p_family_word text, p_hero_label text, p_hero_domain text,
                                                  p_lag_days int, p_travel jsonb, p_rep jsonb, p_watch jsonb, p_quiet boolean, p_url text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare verb text; when_ text; sent text; title text; hook text; share text; dom text := ripples.rm_domain_word(p_hero_domain); n_dom int; days int; depth int; fam_pl text;
begin
  fam_pl := case when lower(p_family_word) = 'person' then 'people' when lower(p_family_word) like '%s' then lower(p_family_word)
                 when lower(p_family_word) like '%y' then left(lower(p_family_word), -1) || 'ies' else lower(p_family_word) || 's' end;
  n_dom := coalesce((p_travel ->> 'domains_crossed')::int, 1); days := (p_travel ->> 'days')::int; depth := coalesce((p_travel ->> 'depth')::int, 1);
  when_ := case when p_lag_days is null then 'later' when p_lag_days = 0 then 'the same day' when p_lag_days = 1 then 'a day later'
                when p_lag_days >= 21 then round(p_lag_days / 7.0) || ' weeks later' else p_lag_days || ' days later' end;
  verb := case p_kind when 'non_event' then 'never showed up in' when 'watching' then 'might be showing up in'
               else case when p_tier = 'measured' then 'showed up in' else 'may have shown up in' end end;
  if p_kind = 'pattern' then
    sent := format('Across %s past %s, %s %s: %s.', p_rep ->> 'n_similar', lower(p_family_word), p_hero_label,
                   case when coalesce((p_rep ->> 'effect')::numeric, 0) >= 0 then 'rose' else 'fell' end,
                   case when (p_rep ->> 'unit') = 'raw' then (p_rep ->> 'effect') || ' raw units' else abs((p_rep ->> 'effect')::numeric) || '%' end || ' vs unaffected regions');
    title := p_family_word || ' → ' || p_hero_label;
    hook := 'Seen across ' || (p_rep ->> 'n_similar') || ' past events, not one.';
    share := title || ' · ' || (p_rep ->> 'effect') || case when (p_rep ->> 'unit') = 'raw' then ' raw' else '%' end || ' across ' || (p_rep ->> 'n_similar') || ' past events · a pattern, never proof of cause · ' || coalesce(p_url, '');
  elsif p_kind = 'non_event' and p_archetype = 'Ghost' then
    sent := format('%s was expected to ripple outward. Every path we watched stayed flat.', p_event_label);
    title := p_event_label || ': the ripple that died';
    hook := 'Everybody expected a ripple. Nothing moved.';
    share := title || ' · ' || coalesce(p_travel ->> 'expected_stops', '?') || ' expected stops, none moved · ' || coalesce(p_url, '');
  elsif p_kind = 'non_event' then
    sent := format('%s was expected to ripple into %s%s. It didn''t: we expected a move about 1 in %s times, and the window closed flat.', p_event_label, p_hero_label,
                   case when dom is null then '' else ' (' || lower(dom) || ')' end, coalesce(p_watch ->> 'expected_1_in', '?'));
    title := p_event_label || ' → ' || p_hero_label || ': dead end';
    hook := 'The expected move never came.';
    share := title || ' · stayed flat · ' || coalesce(p_url, '');
  elsif p_kind = 'watching' then
    sent := format('%s %s %s. Too early to tell: the window closes in %s days.', p_event_label, verb, p_hero_label, coalesce(p_watch ->> 'days_to_resolve', '?'));
    title := p_event_label || ' → ' || p_hero_label || '?';
    hook := format('Similar %s: a move by then about 1 in %s times.', fam_pl, coalesce(p_watch ->> 'expected_1_in', '?'));
    share := title || ' · still being watched, closes in ' || coalesce(p_watch ->> 'days_to_resolve', '?') || ' days · ' || coalesce(p_url, '');
  else
    sent := case when n_dom >= 2 and depth >= 2 then format('%s didn''t stop at %s — %s it %s %s, %s domains away.', p_event_label, lower(dom), when_, verb, p_hero_label, n_dom)
                 when p_archetype = 'Blind Spot' then format('%s %s %s — not where %s usually land.', p_event_label, verb, p_hero_label, fam_pl)
                 when p_archetype = 'Delay' then format('Nothing, nothing, then %s: %s %s %s.', when_, p_event_label, verb, p_hero_label)
                 when p_archetype = 'Funnel' then format('%s %s %s from several directions at once.', p_event_label, verb, p_hero_label)
                 when p_archetype in ('Echo','Branch') then format('%s %s %s — and %s other domains answered.', p_event_label, verb, p_hero_label, n_dom - 1)
                 when p_archetype = 'Bounce' then format('%s %s %s — in the opposite direction from the one we registered.', p_event_label, verb, p_hero_label)
                 when p_archetype = 'Shared Stop' then format('%s and another event both reached %s. A shared stop, not a chain.', p_event_label, p_hero_label)
                 else format('%s %s %s %s.', p_event_label, when_, verb, p_hero_label) end;
    title := p_event_label || ' → ' || p_hero_label;
    hook := case when p_rep is not null and coalesce((p_rep ->> 'n_seen')::int, 0) > 0 then format('Seen after %s of %s similar events.', p_rep ->> 'n_seen', p_rep ->> 'n_similar')
                 when p_lag_days is not null and p_lag_days >= 7 then format('The surprising part: it showed up %s.', when_)
                 when n_dom >= 2 then format('It crossed %s domains.', n_dom)
                 when p_tier = 'measured' then 'Measured, and it survived the lookalike test.'
                 else 'Probably linked; a fluke isn''t ruled out.' end;
    share := title || ' · ' || case when p_tier = 'measured' then 'Measured' when p_tier = 'likely' then 'Likely' else p_tier end
             || case when days is not null then ' · ' || days || case when days = 1 then ' day' else ' days' end else '' end
             || case when n_dom >= 2 then ' · ' || n_dom || ' domains' else '' end || ' · consistent with, never proof of cause · ' || coalesce(p_url, '');
  end if;
  if p_quiet and p_kind <> 'pattern' then hook := null; end if;   -- quiet mode: no playful hook on a sensitive event (patterns are aggregates)
  return jsonb_build_object('story_sentence', sent, 'short_title', title, 'conversation_hook', hook, 'share_line', share);
end $$;
-- coherence gate: featurable only if both coherences pass and every node has a public name
create or replace function ripples.att_story_gate(p_fields jsonb, p_cfg jsonb) returns text
language sql immutable set search_path = '' as $$
  select case when coalesce((p_fields ->> 'temporal_coherence')::float8, 0) < coalesce((p_cfg -> 'gates' ->> 'temporal_min')::float8, 0.5) then 'low temporal coherence'
              when coalesce((p_fields ->> 'mechanism_coherence')::float8, 0) < coalesce((p_cfg -> 'gates' ->> 'mechanism_min')::float8, 0.4) then 'no mechanism at a transition ("and then somehow")'
              when not coalesce((p_fields ->> 'labels_ok')::boolean, false) then 'waiting for a public name'
              else null end
$$;
-- Archetypes (D-14 + D-15 merged; presentation labels only). Deterministic rules on story fields; all matches returned, first = primary.
-- Precedence: Ghost > Collapse > Shared Stop > Detour > Branch > Echo > Funnel > Bounce > Amplifier > Blind Spot > Delay.
--   Ghost       : story_kind ghost — the event pre-registered ≥ ghost_min_expected expected stops (p_hat > 0), every window closed, nothing moved (no Likely+ anywhere).
--   Collapse    : story_kind non_event — ONE pre-registered expected stop (p_hat ≥ collapse_min_p_hat) whose window closed flat.
--   Shared Stop : the hero's attribution share < 0.5 with named rivals, or another public event has a Likely+ stop on the same node within ±14 d.
--   Detour      : length ≥ 2 with every edge 'chain' (mediation supported), ≥ 2 distinct domains and surprise ≥ 0.5.
--   Branch      : ≥ 3 distinct domains reached by Likely+ stops at depth 1 of the same event.
--   Echo        : 2 distinct domains reached by Likely+ stops at depth 1 (several independent domains respond).
--   Funnel      : ≥ 2 Likely+ sibling stops (same parent) land in the SAME domain (e.g. FEMA declarations in FL, NC, SC).
--   Bounce      : direction opposite to the pre-registered / template sign (rho < 1 where + expected, > 1 where − expected), or a pattern 'unexpected direction'.
--   Amplifier   : magnitude ≥ 0.8 with shock ≤ 0.4 (small stone, big ripple), or a child stop's |log effect| > 1.5× its parent's.
--   Blind Spot  : tier ≥ Likely and surprise ≥ 0.6 and counterintuitiveness ≥ 0.6 (far from the family's usual domains AND not what the mechanism library expects; p8 2026-09-26).
--   Delay       : tier ≥ Likely and (hero lag ≥ 7 d or the hero's channel window ≥ 28 d): nothing, nothing, then "9 days later".
-- Watching stories carry no archetype (kind 'watching' is the anticipation object itself). Patterns: Bounce / Blind Spot or none.
create or replace function ripples.att_story_archetypes(p_kind text, p_fields jsonb, p_cfg jsonb default null) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_kind = 'ghost' then 'Ghost' end,
    case when p_kind = 'non_event' then 'Dead end' end,      -- D-16 vocabulary; D-15 'Collapse' is the same object
    case when p_kind = 'non_event' then 'Collapse' end,
    case when p_kind in ('cascade','pattern') and coalesce((p_fields ->> 'shared_stop')::boolean, false) then 'Shared Stop' end,
    case when p_kind = 'cascade' and coalesce((p_fields ->> 'length')::int, 1) >= 2 and coalesce((p_fields ->> 'mediation_supported')::boolean, false)
              and coalesce((p_fields ->> 'domain_diversity')::int, 0) >= 2 and coalesce((p_fields ->> 'surprise')::float8, 0) >= 0.5 then 'Detour' end,
    case when p_kind = 'cascade' and coalesce((p_fields ->> 'event_domains_likely')::int, 0) >= 3 then 'Branch' end,
    case when p_kind = 'cascade' and coalesce((p_fields ->> 'event_domains_likely')::int, 0) = 2 then 'Echo' end,
    case when p_kind = 'cascade' and coalesce((p_fields ->> 'funnel_siblings')::int, 0) >= 2 then 'Funnel' end,
    case when p_kind in ('cascade','pattern') and coalesce((p_fields ->> 'direction_unexpected')::boolean, false) then 'Bounce' end,
    case when p_kind in ('cascade','pattern') and ((coalesce((p_fields ->> 'magnitude')::float8, 0) >= 0.8 and coalesce((p_fields ->> 'shock')::float8, 1) <= 0.4)
                                                    or coalesce((p_fields ->> 'amplified_child')::boolean, false)) then 'Amplifier' end,
    case when p_kind in ('cascade','pattern') and coalesce((p_fields ->> 'evidence_at_transitions')::float8, 0) >= 0.5
              and coalesce((p_fields ->> 'surprise')::float8, 0) >= 0.6 and coalesce((p_fields ->> 'counterintuitiveness')::float8, 0) >= 0.6 then 'Blind Spot' end,
    case when p_kind = 'cascade' and coalesce((p_fields ->> 'evidence_at_transitions')::float8, 0) >= 0.5
              and (coalesce((p_fields ->> 'hero_lag_days')::float8, 0) >= 7 or coalesce((p_fields ->> 'hero_window_days')::int, 0) >= 28) then 'Delay' end
  ], null)
$$;
-- tier wording (ENGINE §8 templates; the Measured sentence is never produced for any other tier)
create or replace function ripples.att_story_tier_wording(p_tier text, p_kind text default 'cascade') returns text
language sql immutable set search_path = '' as $$
  select case when p_kind = 'pattern' then 'A pattern across past events, not evidence about any one event. Consistent with, never proof of cause.'
              when p_kind in ('non_event','ghost') then 'Expected to move; it stayed flat. The window closed without a detectable move.'
              when p_tier = 'measured' then 'Measured movement, not proof of cause.'
              when p_tier = 'likely' then 'Probably linked; a fluke isn''t ruled out.'
              when p_tier = 'watching' then 'Too early to tell. The mechanism exists; no measurable move yet.'
              when p_tier = 'retracted' then 'Retracted.'
              else 'Stayed flat.' end
$$;
create or replace function ripples.att_story_fields_doc() returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'temporal_coherence', 'min over stops of order_ok × lag plausibility (lag vs the template/channel window L; child onset never before its parent)',
    'mechanism_coherence', 'min over stops of the frozen path''s mechanism support (MAP/MECH 1, WD 0.7, CS/GK 0.5, WIKI 0.4, none 0)',
    'evidence_at_transitions', 'min over stops of the tier score (Measured 1, Likely 0.6, provisional 0.5, Watching 0.2)',
    'domain_diversity', 'distinct public domains among the story''s stops (scaled by diversity_full_at for the score)',
    'surprise', '0.5 × (1 − share of the hero''s domain among the family''s frozen candidates) + 0.5 × engine hiddenness H',
    'magnitude', 'normalised |log effect| of the hero vs its baseline (effect_full_scale_logpts); shock = the event''s stone (family percent rank of magnitude)',
    'replication', '6.2 family pool for (family[, hurricane sub], outcome source): n_seen / n_similar (moved in the expected direction), n_strict (passed the regional contrast)',
    'independent_confirmations', 'agreeing channels + this event''s regional contrast pass + the forecast check agreeing',
    'branching_noise', 'share of the event''s depth-1 tests that stayed flat', 'length', 'stops along the spine', 'visual_clarity', '(1/(1+noise)) × (1 − 0.15(length−1)) × names',
    'common_cause_risk', 'max over non-root stops: 1 fork by engine test, 0.6 unevaluated, 0 mediated; root: 0.5×rival attribution + 0.5×common-shock day',
    'novelty', '1 new; 0.75 same family featured in novelty_days; 0.5 same family+domain; 0.25 same event; 0 same story',
    'shareability', '0.4×hero tier + 0.2×magnitude + 0.2×names + 0.1×replication + 0.1×not quiet')
$$;
revoke all on function ripples.att_story_tier_score(text, boolean), ripples.att_story_edge_kind(jsonb, jsonb), ripples.att_story_public_tier(text, jsonb),
  ripples.att_story_mech_support(jsonb), ripples.att_story_lag_plaus(float8, int), ripples.att_story_effect_norm(float8, text, jsonb),
  ripples.att_story_score(jsonb, jsonb), ripples.att_story_gate(jsonb, jsonb), ripples.att_story_archetypes(text, jsonb, jsonb),
  ripples.att_story_tier_wording(text, text), ripples.att_story_fields_doc(),
  ripples.att_story_copy(text, text, text, text, text, text, text, int, jsonb, jsonb, jsonb, boolean, text) from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Table-reading helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- share of a family's frozen candidates landing in a public domain (the family's "usual" domains); decoys excluded
create or replace function ripples.att_story_family_domain_share(p_family text, p_domain text) returns real
language sql stable security definer set search_path = '' as $$
  select coalesce((count(*) filter (where ripples.rm_domain8(ripples.rm_domain(c.channels[1])) = p_domain))::real / nullif(count(*), 0), 0)
    from ripples.att_hop_candidates c join ripples.att_events e on e.event_id = c.event_id
   where e.family = p_family and e.role <> 'decoy' and c.frozen_hash is not null
$$;
-- the event's stone: family percent rank of its magnitude (6.2 helper), falling back to the family incl. live events
create or replace function ripples.att_story_shock_norm(p_event bigint) returns real
language sql stable security definer set search_path = '' as $$
  select coalesce(ripples.att_fx_shock_norm(p_event),
    (select case when e.magnitude is null then null else
       (select (count(*) filter (where x.magnitude < e.magnitude))::real / greatest(count(*) - 1, 1)
          from ripples.att_events x where x.family = e.family and x.role <> 'decoy' and x.magnitude is not null) end
       from ripples.att_events e where e.event_id = p_event))
$$;
-- Sensitivity policy (coordinator follow-up 2026-09-26): `sensitivity.quiet` (rm_sensitive: engine flag OR hazard.* family) means QUIET
-- PRESENTATION (no celebratory copy / animation) and never exclusion: hurricanes stay candidates and replication examples. The only
-- exclusion is an off-limits event: deaths or violence involving individuals (label regex) or a family listed in att_config story.off_limits_families.
create or replace function ripples.att_story_off_limits(p_event bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(e.label ~* coalesce(ripples._att_cfg('story') ->> 'off_limits_regex', '\m(killed|killing|murder|shooting|massacre|suicide|stabbing|victims?|died|death of|dies|funeral|obituary|rape|assault)\M'), false)
         or e.family = any (coalesce(array(select jsonb_array_elements_text(ripples._att_cfg('story') -> 'off_limits_families')), '{}'))
    from ripples.att_events e where e.event_id = p_event
$$;
revoke all on function ripples.att_story_off_limits(bigint) from anon, authenticated, public;
-- 6.2 replication for (event, node): the frozen pair whose outcome source is the node's source (hurricane sub-pair preferred)
create or replace function ripples.att_story_replication(p_event bigint, p_node text) returns jsonb
language sql stable security definer set search_path = '' as $$
  with ev as (select e.*, (t.meta ? 'storm') as is_hurricane from ripples.att_events e left join ripples.att_topics t on t.topic_id = e.topic_id where e.event_id = p_event),
  g as (select fe.*, ev.is_hurricane from ripples.att_family_effects fe, ev
         where fe.family = ev.family and fe.source = split_part(p_node, ':', 1) and fe.n_events is not null
           and (fe.sub is null or (fe.sub = 'hurricane' and ev.is_hurricane))
         order by (fe.sub is not null) desc limit 1),
  own as (select f.* from ripples.att_fx_event f, g where f.grid_id = g.grid_id and f.event_id = p_event and f.role in ('real','live') order by (f.role = 'real') desc limit 1)
  select case when not exists (select 1 from g) then null else (select jsonb_build_object(
    'grid_id', g.grid_id, 'n_similar', g.n_events, 'n_seen', round(coalesce((g.payload ->> 'share_positive')::float8, 0) * g.n_events)::int,
    'n_strict', coalesce((g.payload ->> 'n_regional_pass')::int, 0), 'strength', g.strength, 'effect_pct', g.pct, 'q', g.q, 'p_placebo', g.p_placebo,
    'outcome_label', g.outcome_label, 'sign_expected', g.expected_sign,
    'example_event_ids', coalesce((select jsonb_agg(f0.event_id order by abs(f0.z) desc) from (select * from ripples.att_fx_event f0 where f0.grid_id = g.grid_id and f0.role = 'real' and f0.z is not null
                                                                                            and f0.event_id <> p_event order by abs(f0.z) desc limit 3) f0), '[]'::jsonb),
    'regional', (select jsonb_build_object('d', round(o.d::numeric, 4), 'z', round(o.z::numeric, 2), 'p_space', o.p_space, 'p_pre', o.p_pre, 'p_time', o.p_time,
                                           'pass', coalesce(o.p_space <= 0.05 and o.p_pre >= 0.10 and sign(o.d) = g.expected_sign, false), 'role', o.role) from own o))
    from g) end
$$;
revoke all on function ripples.att_story_family_domain_share(text, text), ripples.att_story_shock_norm(bigint), ripples.att_story_replication(bigint, text)
  from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Build the candidates of one event (cascade / watching / non_event / ghost rows). Reads the engine's published cascade payload.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_story_event(p_event bigint) returns int
language plpgsql security definer set search_path = '' as $fn$
declare ev ripples.att_events; ws jsonb; cfg jsonb := ripples._att_cfg('story'); today date := (now() at time zone 'utc')::date;
        n_written int := 0; root jsonb; nodes jsonb; sub jsonb; n jsonb; e jsonb; edges jsonb; hop_ids bigint[]; k text;
        fields jsonb; t_min real; m_min real; ev_min real; doms text[]; hero jsonb; hero_hop bigint; spine bigint[]; branches bigint[];
        fam_share real; surprise real; shock real; magn real; rep jsonb; conf int; noise real; len int; clarity real; ccr real; med_ok boolean;
        labels_ok boolean; lbl text; nn int; nflat int; quiet boolean; is_ctl boolean; gate jsonb; pub jsonb; arche text[]; score real; coh real;
        excl text; tier_min text; tier_max text; ev_dom_likely int; funnel int; shared boolean; dir_unexp boolean; amp boolean; novelty real; share real;
        hero_lag float8; hero_l int; t ripples.att_hop_tests; c ripples.att_hop_candidates; chain jsonb; parent_onset date; l_days int; plaus real;
        tmpl text; expected_sign int; rho float8; pr jsonb; nd_min text; tier_rank int; r record; n_ghost int; ghost_hops bigint[]; wt jsonb;
        window_open boolean; nxt date; v_phat real; kind text; pp bigint; wj jsonb; v_lag float8; v_onset date; v_off boolean; v_offl boolean; old_fs jsonb; counter real; travel jsonb; cp jsonb; fam_word text; hero_lbl text; url text;
begin
  select * into ev from ripples.att_events where event_id = p_event;
  if not found or ev.role not in ('real','library','positive_control') then return 0; end if;
  select payload into ws from ripples.att_cascades where event_id = p_event;
  select coalesce(jsonb_object_agg(story_id, first_seen), '{}'::jsonb) into old_fs from ripples.att_story_candidates where event_id = p_event;
  select coalesce(f.label, ev.family) into fam_word from ripples.att_families f where f.family = ev.family;
  fam_word := coalesce(fam_word, ev.family);
  delete from ripples.att_story_candidates where event_id = p_event;
  if ws is null then return 0; end if;
  quiet := ripples.rm_sensitive(p_event); is_ctl := ev.role = 'positive_control';   -- sensitivity = QUIET presentation, never exclusion
  v_offl := ripples.att_story_off_limits(p_event);                                     -- the only exclusion: deaths / violence involving individuals
  shock := ripples.att_story_shock_norm(p_event);
  nodes := coalesce(ws -> 'nodes', '[]'::jsonb);
  nn := jsonb_array_length(nodes); nflat := jsonb_array_length(coalesce(ws -> 'flat', '[]'::jsonb));
  noise := case when nn + nflat = 0 then 0 else nflat::real / (nn + nflat) end;
  -- depth-1 Likely+ domains of the whole event (Echo / Branch) and the flat-vs-moved count
  select count(distinct ripples.rm_domain8(x ->> 'domain')) into ev_dom_likely from jsonb_array_elements(nodes) x
   where coalesce((x ->> 'depth')::int, 1) = 1 and x ->> 'tier' in ('measured','likely') and not ripples.rm_node_hidden(x ->> 'node');

  -- ---- cascade + watching stories: one per depth-1 root ----
  for root in select x from jsonb_array_elements(nodes) x
               where coalesce((x ->> 'depth')::int, 1) = 1 and x ->> 'tier' in ('measured','likely','watching') and not ripples.rm_node_hidden(x ->> 'node')
               order by (x ->> 'hop_id')::bigint loop
    kind := case when root ->> 'tier' = 'watching' then 'watching' else 'cascade' end;
    window_open := coalesce((root ->> 'window_close')::date >= today, false);
    if kind = 'watching' and not window_open then continue; end if;                 -- closed Watching windows are pending, not stories
    -- subtree: descendants with a publishable tier
    sub := jsonb_build_array(root);
    loop
      select coalesce(jsonb_agg(x), '[]'::jsonb) into n from jsonb_array_elements(nodes) x
       where x ->> 'tier' in ('measured','likely','watching') and not ripples.rm_node_hidden(x ->> 'node')
         and (x ->> 'parent_hop') is not null
         and exists (select 1 from jsonb_array_elements(sub) s where (s ->> 'hop_id') = (x ->> 'parent_hop'))
         and not exists (select 1 from jsonb_array_elements(sub) s where (s ->> 'hop_id') = (x ->> 'hop_id'));
      exit when jsonb_array_length(n) = 0;
      sub := sub || n;
    end loop;
    hop_ids := array(select (s ->> 'hop_id')::bigint from jsonb_array_elements(sub) s order by coalesce((s ->> 'depth')::int, 1), (s ->> 'hop_id')::bigint);
    -- per-node transition fields
    edges := '[]'::jsonb; t_min := 1; m_min := 1; ev_min := 1; labels_ok := true; med_ok := true; ccr := 0; len := 1; doms := '{}'; amp := false;
    for n in select s from jsonb_array_elements(sub) s order by coalesce((s ->> 'depth')::int, 1), (s ->> 'hop_id')::bigint loop
      select * into c from ripples.att_hop_candidates where hop_id = (n ->> 'hop_id')::bigint;
      select * into t from ripples.att_hop_tests where hop_id = (n ->> 'hop_id')::bigint and tier is not null order by look_no desc limit 1;
      lbl := ripples.rm_label_resolve(n ->> 'node', n ->> 'label');
      if lbl is null then labels_ok := false; end if;
      doms := doms || ripples.rm_domain8(n ->> 'domain');
      len := greatest(len, coalesce((n ->> 'depth')::int, 1));
      -- temporal: order + lag plausibility against the template's L (else the channel's)
      tmpl := c.path -> 0 ->> 'template';
      select mt.l_days into l_days from ripples.att_mech_templates mt where mt.template = tmpl;
      if l_days is null then select cs.l_days into l_days from ripples.att_channel_stat cs where cs.channel = c.channels[1]; end if;
      -- engine reads, in order: payload node.lag_days | att_hop_tests.lag_days | att_hop_tests.detail->>'lag_days' | t_v − t_u (lights up when the engine writes them)
      v_lag := coalesce((n ->> 'lag_days')::float8, t.lag_days::float8, (t.detail ->> 'lag_days')::float8,
                        (coalesce(t.t_v, (t.detail ->> 'onset')::date) - coalesce(t.t_u, c.onset))::float8);
      plaus := ripples.att_story_lag_plaus(v_lag, l_days);
      if coalesce(t.reversed, false) or (t.flags is not null and ('reversed' = any (t.flags) or 'common_cause' = any (t.flags))) then plaus := 0; end if;
      if (n ->> 'parent_hop') is not null then
        select (s ->> 'onset')::date into parent_onset from jsonb_array_elements(sub) s where s ->> 'hop_id' = n ->> 'parent_hop';
        v_onset := coalesce((n ->> 'onset')::date, t.t_v, (t.detail ->> 'onset')::date);
        if parent_onset is not null and v_onset is not null and v_onset < parent_onset then plaus := 0; end if;
      end if;
      t_min := least(t_min, plaus);
      m_min := least(m_min, ripples.att_story_mech_support(c.path));
      ev_min := least(ev_min, ripples.att_story_tier_score(n ->> 'tier', coalesce((n ->> 'provisional')::boolean, false)));
      -- edges: chain only with engine mediation support (hard rule); root: attribution / common shock risk
      if (n ->> 'parent_hop') is null then
        edges := edges || jsonb_build_object('from', 'event', 'to', (n ->> 'hop_id')::bigint, 'kind', 'fork');
        ccr := greatest(ccr, least(1, 0.5 * (case when coalesce((t.attribution ->> 'share')::float8, 1) < 0.5 then 1 else 0 end)
                                       + 0.5 * (case when coalesce(t.common_shock, false) then 1 else 0 end)));
      else
        chain := coalesce(t.detail -> 'chain', t.detail -> 'mediation');   -- engine record {fork_test, mediation_c}: att_hop_tests.detail->'chain' (fallback ->'mediation')
        k := ripples.att_story_edge_kind(chain, n -> 'fork_of');
        edges := edges || jsonb_build_object('from', case when k = 'chain' then to_jsonb((n ->> 'parent_hop')::bigint) else to_jsonb('event'::text) end,
                                             'to', (n ->> 'hop_id')::bigint, 'kind', k, 'engine_parent', (n ->> 'parent_hop')::bigint,
                                             'mediation', case when chain is null then 'not evaluated' when k = 'chain' then 'supported' else 'not supported: fork' end);
        if k <> 'chain' then med_ok := false; end if;
        ccr := greatest(ccr, case when k = 'chain' then 0 when chain is null then 0.6 else 1 end);
        -- Amplifier: child |log effect| > 1.5 × parent's
        select (s ->> 'rho')::float8 into rho from jsonb_array_elements(sub) s where s ->> 'hop_id' = n ->> 'parent_hop';
        if rho is not null and (n ->> 'rho') is not null and rho > 0 and (n ->> 'rho')::float8 > 0
           and abs(ln((n ->> 'rho')::float8)) > 1.5 * abs(ln(rho)) and abs(ln(rho)) > 0.02 then amp := true; end if;
      end if;
    end loop;
    -- hero: highest tier, then largest effect, then most hidden; spine = chain path event → hero; branches = the rest
    select s into hero from jsonb_array_elements(sub) s
     order by ripples.att_story_tier_score(s ->> 'tier', coalesce((s ->> 'provisional')::boolean, false)) desc,
              coalesce(ripples.att_story_effect_norm((s ->> 'rho')::float8, s ->> 'unit', cfg -> 'scales'), 0) desc,
              coalesce((s ->> 'hidden')::float8, 0) desc, (s ->> 'hop_id')::bigint limit 1;
    hero_hop := (hero ->> 'hop_id')::bigint;
    spine := array[hero_hop];
    loop
      pp := null;
      select (ed ->> 'engine_parent')::bigint into pp from jsonb_array_elements(edges) ed where (ed ->> 'to')::bigint = spine[1] and ed ->> 'kind' = 'chain';
      exit when pp is null or pp = any (spine);
      spine := array[pp] || spine;
    end loop;
    branches := array(select h from unnest(hop_ids) h where h <> all (spine));
    -- story-level fields
    fam_share := ripples.att_story_family_domain_share(ev.family, ripples.rm_domain8(hero ->> 'domain'));
    surprise := 0.5 * (1 - fam_share) + 0.5 * coalesce((hero ->> 'hidden')::float8, 0.5);
    magn := ripples.att_story_effect_norm((hero ->> 'rho')::float8, hero ->> 'unit', cfg -> 'scales');
    rep := ripples.att_story_replication(p_event, hero ->> 'node');
    select * into t from ripples.att_hop_tests where hop_id = hero_hop and tier is not null order by look_no desc limit 1;
    select * into c from ripples.att_hop_candidates where hop_id = hero_hop;
    gate := case when root ->> 'tier' = 'measured' then ripples.att_ce_gate((root ->> 'hop_id')::bigint, 'measured') end;
    pub := ripples.att_story_public_tier(root ->> 'tier', gate);
    conf := coalesce((hero -> 'channels' ->> 'agree')::int, 0) + (case when coalesce((rep -> 'regional' ->> 'pass')::boolean, false) then 1 else 0 end)
            + (case when coalesce((gate -> 'ce' ->> 'n_agree')::int, 0) > 0 then 1 else 0 end);
    select count(*) into funnel from jsonb_array_elements(nodes) x
     where x ->> 'tier' in ('measured','likely') and (x ->> 'parent_hop') is not distinct from (root ->> 'parent_hop')
       and ripples.rm_domain8(x ->> 'domain') = ripples.rm_domain8(root ->> 'domain') and (x ->> 'hop_id')::bigint <> (root ->> 'hop_id')::bigint;
    funnel := case when root ->> 'tier' in ('measured','likely') then funnel + 1 else 0 end;   -- siblings incl. the root itself
    shared := (coalesce((t.attribution ->> 'share')::float8, 1) < 0.5 and jsonb_array_length(coalesce(t.attribution -> 'rivals', '[]'::jsonb)) > 0)
              or exists (select 1 from ripples.att_hop_candidates c2 join ripples.att_events e2 on e2.event_id = c2.event_id
                           join ripples.att_hop_tests t2 on t2.hop_id = c2.hop_id and t2.tier in ('measured','likely')
                          where c2.node = hero ->> 'node' and c2.event_id <> p_event and e2.role in ('real','library','positive_control')
                            and abs(e2.onset - ev.onset) <= 14 and exists (select 1 from ripples.rm_public_versions v where v.event_id = e2.event_id));
    expected_sign := coalesce(c.sign, (c.path -> 0 ->> 'sign')::int, 0);
    rho := (hero ->> 'rho')::float8;
    dir_unexp := expected_sign <> 0 and rho is not null and ((coalesce(hero ->> 'unit', 'x') = 'x' and ((expected_sign > 0 and rho < 1) or (expected_sign < 0 and rho > 1)))
                                                            or (hero ->> 'unit' = 'points' and sign(rho) = -expected_sign));
    hero_lag := coalesce((hero ->> 'lag_days')::float8, t.lag_days::float8, (t.detail ->> 'lag_days')::float8);
    select mt.l_days into hero_l from ripples.att_mech_templates mt where mt.template = c.path -> 0 ->> 'template';
    if hero_l is null then select cs.l_days into hero_l from ripples.att_channel_stat cs where cs.channel = c.channels[1]; end if;
    clarity := (1 / (1 + noise)) * greatest(0, 1 - 0.15 * (len - 1)) * (case when labels_ok then 1 else 0.3 end);
    select case when exists (select 1 from ripples.att_story_featured f where f.story_id = kind || ':' || p_event || ':' || (root ->> 'hop_id') and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0
                when exists (select 1 from ripples.att_story_featured f where f.event_id = p_event and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0.25
                when exists (select 1 from ripples.att_story_featured f where f.family = ev.family and f.domain = ripples.rm_domain8(hero ->> 'domain') and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0.5
                when exists (select 1 from ripples.att_story_featured f where f.family = ev.family and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0.75
                else 1 end into novelty;
    share := 0.4 * ripples.att_story_tier_score(pub ->> 'tier', coalesce((hero ->> 'provisional')::boolean, false)) + 0.2 * coalesce(magn, 0)
             + 0.2 * (case when labels_ok then 1 else 0 end) + 0.1 * (case when rep is not null then 1 else 0 end) + 0.1 * (case when quiet then 0 else 1 end);
    select min(x.t), max(x.t) into tier_min, tier_max from (select s ->> 'tier' t from jsonb_array_elements(sub) s) x;   -- alphabetical: likely < measured < watching; recomputed below by rank
    select (array['watching','likely','measured'])[min(rk)], (array['watching','likely','measured'])[max(rk)] into tier_min, tier_max
      from (select case s ->> 'tier' when 'measured' then 3 when 'likely' then 2 else 1 end rk from jsonb_array_elements(sub) s) x;
    -- D-16: counterintuitiveness (surprising destination / cross-domain) and "how far did it travel?"
    counter := least(1, 0.5 * surprise + 0.5 * (case when fam_share <= 0.10 then 1 when fam_share <= 0.25 then 0.6 when fam_share <= 0.5 then 0.3 else 0 end));
    travel := jsonb_build_object('domains_crossed', (select count(distinct d) from unnest(doms) d),
                                 'days', (select max(greatest(0, coalesce((s ->> 'onset')::date - ev.onset, (s ->> 'lag_days')::int))) from jsonb_array_elements(sub) s),
                                 'depth', len);
    fields := jsonb_build_object('counterintuitiveness', round(counter::numeric, 3), 'travel', travel) || jsonb_build_object(
      'temporal_coherence', round(t_min::numeric, 3), 'mechanism_coherence', round(m_min::numeric, 3), 'evidence_at_transitions', round(ev_min::numeric, 3),
      'domain_diversity', (select count(distinct d) from unnest(doms) d), 'domain_diversity_scaled', least(1, (select count(distinct d) from unnest(doms) d)::float8 / coalesce((cfg -> 'scales' ->> 'diversity_full_at')::float8, 3)),
      'surprise', round(surprise::numeric, 3), 'family_domain_share', round(fam_share::numeric, 3), 'hidden', hero -> 'hidden',
      'magnitude', round(coalesce(magn, 0)::numeric, 3), 'magnitude_known', magn is not null, 'shock', round(coalesce(shock, 0.5)::numeric, 3), 'shock_known', shock is not null,
      'replication', case when rep is null then 0 else least(1, coalesce((rep ->> 'n_seen')::float8, 0) / greatest(coalesce((rep ->> 'n_similar')::float8, 1), 1)) end,
      'independent_confirmations', conf, 'independent_confirmations_scaled', least(1, conf / 3.0),
      'branching_noise', round(noise::numeric, 3), 'length', len, 'visual_clarity', round(clarity::numeric, 3),
      'common_cause_risk', round(ccr::numeric, 3), 'mediation_supported', med_ok, 'labels_ok', labels_ok,
      'novelty', novelty, 'shareability', round(share::numeric, 3), 'visual_density', nn + nflat,
      'event_domains_likely', ev_dom_likely, 'funnel_siblings', funnel, 'shared_stop', shared, 'direction_unexpected', dir_unexp, 'amplified_child', amp,
      'hero_lag_days', hero_lag, 'hero_window_days', hero_l, 'expected_sign', expected_sign);
    -- the score reads the SCALED variants for the count-type fields
    wt := fields || jsonb_build_object('domain_diversity', fields -> 'domain_diversity_scaled', 'independent_confirmations', fields -> 'independent_confirmations_scaled');
    score := ripples.att_story_score(wt, cfg);
    coh := round(((t_min + m_min) / 2)::numeric, 3);
    excl := ripples.att_story_gate(fields, cfg);
    if excl is null and kind = 'cascade' and (root ->> 'tier') = 'likely' and coalesce(root ->> 'tier_reason', '') like '%attention ripple%' and (root ->> 'kind') = 'attention' then
      excl := 'attention-only ripple (never the hero)';
    end if;
    if excl is null and (root ->> 'retracted') is not null and jsonb_typeof(root -> 'retracted') <> 'null' then excl := 'retracted'; end if;
    -- D-16 scope: person → person/attention lines (celebrity → celebrity) are off the core vision (events → real-world downstream impacts)
    if excl is null and ev.family = 'person' and ripples.rm_domain8(hero ->> 'domain') in ('reading','chatter') then excl := 'off_vision_person_attention'; end if;
    if excl is null and v_offl then excl := 'off_limits'; end if;
    arche := ripples.att_story_archetypes(kind, fields, cfg);
    nxt := (select min(d) from ripples.att_hop_candidates hc, unnest(hc.looks) d where hc.hop_id = (root ->> 'hop_id')::bigint and d >= today);
    select rg.p_hat into v_phat from ripples.att_hop_registry rg where rg.hop_id = (root ->> 'hop_id')::bigint;
    v_phat := coalesce(v_phat, (root ->> 'p_hat')::real);
    hero_lbl := ripples.rm_label_resolve(hero ->> 'node', hero ->> 'label');
    url := 'https://bensunter.com/ripples/line/' || ripples.rm_slug(p_event) || '/stop/' || hero_hop || '/';
    wj := case when kind = 'watching' then jsonb_build_object('window_close', root -> 'window_close', 'next_look', nxt, 'days_to_resolve', greatest(0, (root ->> 'window_close')::date - today),
                                                              'p_hat', v_phat, 'expected_1_in', ripples.rm_one_in(v_phat, 50), 'tier_reason', root -> 'tier_reason') end;
    cp := case when hero_lbl is null then null else
            ripples.att_story_copy(kind, arche[1], pub ->> 'tier', ev.label, fam_word, hero_lbl, ripples.rm_domain8(hero ->> 'domain'), (hero ->> 'lag_days')::int, travel,
                                   case when rep is null then null else rep || jsonb_build_object('effect', rep -> 'effect_pct') end, wj, quiet, url) end;
    insert into ripples.att_story_candidates (story_id, story_kind, event_id, grid_id, root_hop, hop_ids, engine_tier, tier, gate, tier_min, tier_max, fields, graph,
        archetype, archetypes, hero_stop, spine, branches, story_score, coherence_score, featurable, exclude_reason, watching, replication, sensitivity, copy, travel, first_seen)
    values (kind || ':' || p_event || ':' || (root ->> 'hop_id'), kind, p_event, (rep ->> 'grid_id')::int, (root ->> 'hop_id')::bigint, hop_ids,
        root ->> 'tier', pub ->> 'tier', pub || jsonb_build_object('ce', gate -> 'ce'), tier_min, tier_max, fields,
        jsonb_build_object('nodes', (select jsonb_agg(jsonb_build_object('hop_id', (s ->> 'hop_id')::bigint, 'depth', coalesce((s ->> 'depth')::int, 1), 'node', s ->> 'node',
                                        'domain', ripples.rm_domain8(s ->> 'domain'), 'kind', s ->> 'kind', 'tier', s ->> 'tier', 'provisional', coalesce((s ->> 'provisional')::boolean, false),
                                        'rho', s -> 'rho', 'unit', coalesce(s ->> 'unit', 'x'), 'lag_days', s -> 'lag_days', 'onset', s -> 'onset', 'window_close', s -> 'window_close',
                                        'p_1_in', s -> 'p_1_in', 'f_1_in', s -> 'f_1_in', 'channels', s -> 'channels', 'hidden', s -> 'hidden') order by coalesce((s ->> 'depth')::int, 1), (s ->> 'hop_id')::bigint)
                                      from jsonb_array_elements(sub) s), 'edges', edges),
        arche[1], coalesce(arche, '{}'), hero_hop, spine, branches, score, coh,
        excl is null and (kind = 'cascade' or (kind = 'watching' and v_phat is not null)), coalesce(excl, case when kind = 'watching' and v_phat is null then 'no pre-registered expectation' end),
        wj, rep, jsonb_build_object('quiet', quiet, 'family', ev.family, 'is_control', is_ctl), cp, travel,
        coalesce((old_fs ->> (kind || ':' || p_event || ':' || (root ->> 'hop_id')))::timestamptz, now()));
    n_written := n_written + 1;
  end loop;

  -- ---- non-events: pre-registered expected stops (p_hat > 0) whose window closed flat; Ghost when the whole event stayed flat ----
  select array_agg(rg.hop_id order by rg.hop_id) into ghost_hops
    from ripples.att_hop_registry rg join ripples.att_hop_candidates c2 on c2.hop_id = rg.hop_id
   where c2.event_id = p_event and c2.role in ('real','library','positive_control') and rg.p_hat > 0 and c2.window_close < today
     and not ripples.rm_node_hidden(c2.node)
     and exists (select 1 from ripples.att_hop_tests t2 where t2.hop_id = rg.hop_id and t2.tier = 'flat'
                    and t2.look_no = (select max(t3.look_no) from ripples.att_hop_tests t3 where t3.hop_id = rg.hop_id and t3.tier is not null))
     and not exists (select 1 from jsonb_array_elements(nodes) x where (x ->> 'hop_id')::bigint = rg.hop_id and x ->> 'tier' in ('measured','likely','watching'));
  n_ghost := coalesce(cardinality(ghost_hops), 0);
  if n_ghost > 0 then
    if n_ghost >= coalesce((cfg -> 'gates' ->> 'ghost_min_expected')::int, 3)
       and not exists (select 1 from jsonb_array_elements(nodes) x where x ->> 'tier' in ('measured','likely')) then
      -- one event-level Ghost
      labels_ok := not exists (select 1 from ripples.att_hop_candidates c2 where c2.hop_id = any (ghost_hops) and ripples.rm_label_resolve(c2.node, ripples.att_node_label(c2.node)) is null);
      select avg(rg.p_hat) into v_phat from ripples.att_hop_registry rg where rg.hop_id = any (ghost_hops);
      v_off := (ev.family = 'person' and not exists (select 1 from ripples.att_hop_candidates c2 where c2.hop_id = any (ghost_hops) and ripples.rm_domain8(ripples.rm_domain(c2.channels[1])) not in ('reading','chatter'))) or v_offl;
      fields := jsonb_build_object('temporal_coherence', 1, 'mechanism_coherence', 1, 'evidence_at_transitions', 0, 'domain_diversity', 0, 'surprise', round((1 - coalesce(v_phat, 0))::numeric, 3),
                                   'magnitude', 0, 'shock', round(coalesce(shock, 0.5)::numeric, 3), 'replication', 0, 'independent_confirmations', 0, 'branching_noise', round(noise::numeric, 3),
                                   'length', 1, 'visual_clarity', round((1 / (1 + noise))::numeric, 3), 'common_cause_risk', 0, 'mediation_supported', true, 'labels_ok', labels_ok,
                                   'novelty', 1, 'shareability', round((0.2 + 0.2 * (case when labels_ok then 1 else 0 end) + 0.1 * (case when quiet then 0 else 1 end))::numeric, 3),
                                   'visual_density', nn + nflat, 'expected_stops', n_ghost, 'expected_p_hat', v_phat, 'counterintuitiveness', round((1 - coalesce(v_phat, 0))::numeric, 3));
      travel := jsonb_build_object('domains_crossed', 0, 'days', null, 'depth', 0, 'expected_stops', n_ghost);
      url := 'https://bensunter.com/ripples/line/' || ripples.rm_slug(p_event) || '/';
      cp := case when not labels_ok then null else ripples.att_story_copy('non_event', 'Ghost', 'flat', ev.label, fam_word, ev.label, null, null, travel, null,
                                                                           jsonb_build_object('expected_1_in', ripples.rm_one_in(v_phat, 50)), quiet, url) end;
      insert into ripples.att_story_candidates (story_id, story_kind, event_id, root_hop, hop_ids, engine_tier, tier, gate, tier_min, tier_max, fields, graph, archetype, archetypes,
          hero_stop, spine, branches, story_score, coherence_score, featurable, exclude_reason, watching, replication, sensitivity, copy, travel, first_seen)
      values ('ghost:' || p_event, 'non_event', p_event, ghost_hops[1], ghost_hops, 'flat', 'flat', jsonb_build_object('demoted', false), 'flat', 'flat', fields,
          jsonb_build_object('nodes', (select jsonb_agg(jsonb_build_object('hop_id', c2.hop_id, 'depth', 1, 'node', c2.node, 'domain', ripples.rm_domain8(ripples.rm_domain(c2.channels[1])), 'tier', 'flat',
                                                                          'window_close', c2.window_close, 'p_hat', (select rg.p_hat from ripples.att_hop_registry rg where rg.hop_id = c2.hop_id)) order by c2.hop_id)
                                          from ripples.att_hop_candidates c2 where c2.hop_id = any (ghost_hops)),
                             'edges', (select jsonb_agg(jsonb_build_object('from', 'event', 'to', h, 'kind', 'fork')) from unnest(ghost_hops) h)),
          'Ghost', array['Ghost'], ghost_hops[1], array[ghost_hops[1]], ghost_hops[2:],
          ripples.att_story_score(fields || jsonb_build_object('surprise', round((1 - coalesce(v_phat, 0))::numeric, 3)), cfg), 1,
          labels_ok and not v_off, case when not labels_ok then 'waiting for a public name' when v_offl then 'off_limits' when v_off then 'off_vision_person_attention' end,
          jsonb_build_object('expected_1_in', ripples.rm_one_in(v_phat, 50), 'p_hat', v_phat, 'resolved', 'flat'), null,
          jsonb_build_object('quiet', quiet, 'family', ev.family, 'is_control', is_ctl), cp, travel, coalesce((old_fs ->> ('ghost:' || p_event))::timestamptz, now()));
      n_written := n_written + 1;
    else
      for r in select c2.*, rg.p_hat ph from ripples.att_hop_candidates c2 join ripples.att_hop_registry rg on rg.hop_id = c2.hop_id where c2.hop_id = any (ghost_hops) loop
        continue when r.ph < coalesce((cfg -> 'gates' ->> 'collapse_min_p_hat')::real, 0.15);
        lbl := ripples.rm_label_resolve(r.node, ripples.att_node_label(r.node));
        rep := ripples.att_story_replication(p_event, r.node);
        fam_share := ripples.att_story_family_domain_share(ev.family, ripples.rm_domain8(ripples.rm_domain(r.channels[1])));
        fields := jsonb_build_object('temporal_coherence', 1, 'mechanism_coherence', ripples.att_story_mech_support(r.path), 'evidence_at_transitions', 0, 'domain_diversity', 1,
                                     'domain_diversity_scaled', 1.0 / coalesce((cfg -> 'scales' ->> 'diversity_full_at')::float8, 3), 'surprise', round((0.5 * (1 - fam_share) + 0.5 * r.ph)::numeric, 3),
                                     'magnitude', 0, 'shock', round(coalesce(shock, 0.5)::numeric, 3),
                                     'replication', case when rep is null then 0 else least(1, coalesce((rep ->> 'n_seen')::float8, 0) / greatest(coalesce((rep ->> 'n_similar')::float8, 1), 1)) end,
                                     'independent_confirmations', 0, 'branching_noise', round(noise::numeric, 3), 'length', 1, 'visual_clarity', round((1 / (1 + noise))::numeric, 3),
                                     'common_cause_risk', 0, 'mediation_supported', true, 'labels_ok', lbl is not null, 'novelty', 1,
                                     'shareability', round((0.1 + 0.2 * (case when lbl is not null then 1 else 0 end) + 0.1 * (case when rep is not null then 1 else 0 end) + 0.1 * (case when quiet then 0 else 1 end))::numeric, 3),
                                     'visual_density', nn + nflat, 'expected_p_hat', r.ph, 'counterintuitiveness', round((0.5 * (1 - fam_share) + 0.5 * r.ph)::numeric, 3));
        excl := ripples.att_story_gate(fields, cfg);
        if excl is null and ev.family = 'person' and ripples.rm_domain8(ripples.rm_domain(r.channels[1])) in ('reading','chatter') then excl := 'off_vision_person_attention'; end if;
        if excl is null and v_offl then excl := 'off_limits'; end if;
        travel := jsonb_build_object('domains_crossed', 0, 'days', null, 'depth', 0);
        url := 'https://bensunter.com/ripples/line/' || ripples.rm_slug(p_event) || '/stop/' || r.hop_id || '/';
        wt := jsonb_build_object('window_close', r.window_close, 'p_hat', r.ph, 'expected_1_in', ripples.rm_one_in(r.ph, 50), 'resolved', 'flat');
        cp := case when lbl is null then null else ripples.att_story_copy('non_event', 'Dead end', 'flat', ev.label, fam_word, lbl, ripples.rm_domain8(ripples.rm_domain(r.channels[1])), null, travel,
                                                                          case when rep is null then null else rep || jsonb_build_object('effect', rep -> 'effect_pct') end, wt, quiet, url) end;
        insert into ripples.att_story_candidates (story_id, story_kind, event_id, grid_id, root_hop, hop_ids, engine_tier, tier, gate, tier_min, tier_max, fields, graph, archetype, archetypes,
            hero_stop, spine, branches, story_score, coherence_score, featurable, exclude_reason, watching, replication, sensitivity, copy, travel, first_seen)
        values ('non_event:' || p_event || ':' || r.hop_id, 'non_event', p_event, (rep ->> 'grid_id')::int, r.hop_id, array[r.hop_id], 'flat', 'flat', jsonb_build_object('demoted', false), 'flat', 'flat', fields,
            jsonb_build_object('nodes', jsonb_build_array(jsonb_build_object('hop_id', r.hop_id, 'depth', 1, 'node', r.node, 'domain', ripples.rm_domain8(ripples.rm_domain(r.channels[1])), 'tier', 'flat',
                                                                             'window_close', r.window_close, 'p_hat', r.ph)),
                               'edges', jsonb_build_array(jsonb_build_object('from', 'event', 'to', r.hop_id, 'kind', 'fork'))),
            'Dead end', array['Dead end','Collapse'], r.hop_id, array[r.hop_id], '{}', ripples.att_story_score(fields, cfg), round(((1 + ripples.att_story_mech_support(r.path)) / 2)::numeric, 3),
            excl is null, excl, wt,
            rep, jsonb_build_object('quiet', quiet, 'family', ev.family, 'is_control', is_ctl), cp, travel, coalesce((old_fs ->> ('non_event:' || p_event || ':' || r.hop_id))::timestamptz, now()));
        n_written := n_written + 1;
      end loop;
    end if;
  end if;
  return n_written;
end $fn$;
revoke all on function ripples.att_story_event(bigint) from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Pattern stories from the 6.2 family pool (one per frozen pair; featurable at 'pattern' or better, never checks / definitional pairs)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_story_patterns() returns int
language plpgsql security definer set search_path = '' as $fn$
declare cfg jsonb := ripples._att_cfg('story'); r record; fields jsonb; n int := 0; strength_score real; pond jsonb; nonobv boolean; arche text[]; excl text; novelty real;
        today date := (now() at time zone 'utc')::date; old_fs jsonb; rep jsonb; cp jsonb; travel jsonb; fam_word text;
begin
  select coalesce(jsonb_object_agg(story_id, first_seen), '{}'::jsonb) into old_fs from ripples.att_story_candidates where story_kind = 'pattern';
  delete from ripples.att_story_candidates where story_kind = 'pattern';
  for r in select v.* from ripples.att_family_effects v where v.ledger_seq is not null and v.computed_at is not null and v.n_events is not null
                                                          and not ripples.rm_node_hidden(v.source || ':' || v.metric) loop
    strength_score := case r.strength when 'strong pattern' then 1 when 'pattern' then 0.7 when 'unexpected direction' then 0.6 when 'hint' then 0.35 else 0 end;
    pond := ripples.att_fx_pond(r.d, r.domain_event, r.domain_outcome, case when r.source = 'noaa.ghcnd' and r.metric = 'temp' then 'raw' else 'pct' end);
    nonobv := r.domain_outcome in ('labor','business','travel','developer');
    select case when exists (select 1 from ripples.att_story_featured f where f.story_id = 'pattern:' || r.grid_id and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0
                when exists (select 1 from ripples.att_story_featured f where f.family = r.family and f.day >= today - coalesce((cfg -> 'gates' ->> 'novelty_days')::int, 14)) then 0.75 else 1 end into novelty;
    fields := jsonb_build_object(
      'temporal_coherence', round(coalesce((r.payload ->> 'n_pretrend_flat')::float8 / nullif(r.n_events, 0), 1)::numeric, 3), 'mechanism_coherence', 1,
      'evidence_at_transitions', strength_score, 'domain_diversity', case when nonobv then 2 else 1 end, 'domain_diversity_scaled', (case when nonobv then 2 else 1 end)::float8 / coalesce((cfg -> 'scales' ->> 'diversity_full_at')::float8, 3),
      'surprise', case when nonobv then 0.8 else 0.3 end, 'magnitude', round(coalesce((pond ->> 'ripple')::float8, 0)::numeric, 3), 'magnitude_known', (pond ->> 'ripple') is not null,
      'shock', round(coalesce((r.payload ->> 'shock_median_norm')::float8, 0.5)::numeric, 3), 'shock_known', (r.payload ->> 'shock_median_norm') is not null,
      'replication', round(coalesce((r.payload ->> 'share_positive')::float8, 0)::numeric, 3),
      'independent_confirmations', (case when coalesce((r.payload ->> 'n_regional_pass')::int, 0) > 0 then 1 else 0 end) + (case when coalesce((r.payload ->> 'n_synth_agree')::float8, 0) > 0.5 * r.n_events then 1 else 0 end) + (case when coalesce(r.p_placebo, 1) <= 0.05 then 1 else 0 end),
      'independent_confirmations_scaled', least(1, ((case when coalesce((r.payload ->> 'n_regional_pass')::int, 0) > 0 then 1 else 0 end) + (case when coalesce((r.payload ->> 'n_synth_agree')::float8, 0) > 0.5 * r.n_events then 1 else 0 end) + (case when coalesce(r.p_placebo, 1) <= 0.05 then 1 else 0 end)) / 3.0),
      'branching_noise', 0, 'length', 1, 'visual_clarity', 1, 'common_cause_risk', 0, 'mediation_supported', true, 'labels_ok', true,
      'novelty', novelty, 'shareability', round((0.4 * strength_score + 0.2 * coalesce((pond ->> 'ripple')::float8, 0) + 0.2 + 0.1 + 0.1)::numeric, 3),
      'visual_density', r.n_events, 'direction_unexpected', r.strength = 'unexpected direction', 'heterogeneity_i2', r.i2, 'is_check', r.is_check, 'definitional', r.definitional,
      'counterintuitiveness', case when nonobv then 0.85 else 0.2 end, 'travel', jsonb_build_object('domains_crossed', case when nonobv then 2 else 1 end, 'days', r.post_n * case r.grain when 'week' then 7 else 1 end, 'depth', 1));
    arche := ripples.att_story_archetypes('pattern', fields, cfg);
    excl := case when r.is_check then 'a pre-registered sanity check, not a finding' when r.definitional then 'definitional pair' when r.strength not in ('strong pattern','pattern') then 'below pattern strength (' || coalesce(r.strength, 'n/a') || ')' end;
    rep := jsonb_build_object('grid_id', r.grid_id, 'n_similar', r.n_events, 'n_seen', round(coalesce((r.payload ->> 'share_positive')::float8, 0) * r.n_events)::int,
                              'n_strict', coalesce((r.payload ->> 'n_regional_pass')::int, 0), 'strength', r.strength, 'effect_pct', r.pct, 'q', r.q, 'p_placebo', r.p_placebo,
                              'outcome_label', r.outcome_label, 'sign_expected', r.expected_sign, 'unit', case when r.source = 'noaa.ghcnd' and r.metric = 'temp' then 'raw' else 'pct' end,
                              'example_event_ids', coalesce((select jsonb_agg(f0.event_id order by abs(f0.z) desc) from (select * from ripples.att_fx_event f0 where f0.grid_id = r.grid_id and f0.role = 'real' and f0.z is not null
                                                             and not exists (select 1 from ripples.att_fx_cluster_dups(r.grid_id, 'real', 0) d where d.event_id = f0.event_id) order by abs(f0.z) desc limit 3) f0), '[]'::jsonb));
    travel := fields -> 'travel';
    fam_word := case when r.sub = 'hurricane' then 'Hurricane' else r.family_label end;
    cp := ripples.att_story_copy('pattern', arche[1], r.strength, fam_word || 's', fam_word || 's', r.outcome_label, r.domain_outcome, null, travel, rep || jsonb_build_object('effect', r.pct), null,
                                 r.family like 'hazard.%', 'https://bensunter.com/ripples/patterns/#p' || r.grid_id);
    insert into ripples.att_story_candidates (story_id, story_kind, event_id, grid_id, root_hop, hop_ids, engine_tier, tier, gate, tier_min, tier_max, fields, graph, archetype, archetypes,
        hero_stop, spine, branches, story_score, coherence_score, featurable, exclude_reason, watching, replication, sensitivity, copy, travel, first_seen)
    values ('pattern:' || r.grid_id, 'pattern', null, r.grid_id, null, '{}', r.strength, r.strength, jsonb_build_object('demoted', false), r.strength, r.strength, fields,
        jsonb_build_object('nodes', jsonb_build_array(jsonb_build_object('grid_id', r.grid_id, 'depth', 1, 'node', r.source || ':' || r.metric, 'domain', r.domain_outcome, 'tier', r.strength)),
                           'edges', jsonb_build_array(jsonb_build_object('from', 'family', 'to', r.grid_id, 'kind', 'fork'))),
        arche[1], coalesce(arche, '{}'), null, '{}', '{}',
        ripples.att_story_score(fields || jsonb_build_object('domain_diversity', fields -> 'domain_diversity_scaled', 'independent_confirmations', fields -> 'independent_confirmations_scaled'), cfg),
        round(((coalesce((fields ->> 'temporal_coherence')::float8, 1) + 1) / 2)::numeric, 3), excl is null, excl, null,
        rep, jsonb_build_object('quiet', r.family like 'hazard.%', 'family', r.family, 'is_control', false), cp, travel,
        coalesce((old_fs ->> ('pattern:' || r.grid_id))::timestamptz, now()));
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke all on function ripples.att_story_patterns() from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Chunked daily refresh (≤ p_budget_s per statement; state in att_state 'story.refresh'); novelty log of today's featured list
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_story_refresh(p_budget_s int default 90) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare st jsonb; today date := (now() at time zone 'utc')::date; t0 timestamptz := clock_timestamp(); cur bigint; r record; n int := 0; nev int := 0; done boolean := false;
begin
  select v into st from ripples.att_state where k = 'story.refresh';
  if st is null or (st ->> 'day')::date < today or (st ->> 'status') = 'done' and (st ->> 'day')::date < today then
    st := jsonb_build_object('day', today, 'cursor', 0, 'status', 'running', 'started', now(), 'rows', 0, 'events', 0);
  end if;
  if (st ->> 'status') = 'done' and (st ->> 'day')::date = today then return st || jsonb_build_object('note', 'already refreshed today'); end if;
  cur := coalesce((st ->> 'cursor')::bigint, 0);
  for r in select e.event_id from ripples.att_events e where e.role in ('real','library','positive_control') and e.event_id > cur
                                                          and exists (select 1 from ripples.att_cascades c where c.event_id = e.event_id) order by e.event_id loop
    exit when extract(epoch from clock_timestamp() - t0) > p_budget_s;
    n := n + ripples.att_story_event(r.event_id); nev := nev + 1; cur := r.event_id;
  end loop;
  done := not exists (select 1 from ripples.att_events e where e.role in ('real','library','positive_control') and e.event_id > cur
                                                             and exists (select 1 from ripples.att_cascades c where c.event_id = e.event_id));
  if done then
    n := n + ripples.att_story_patterns();
    -- novelty log: today's featured order (top 20), written once
    insert into ripples.att_story_featured (day, story_id, rank, family, domain, event_id)
    select today, s.story_id, row_number() over (order by s.story_score desc, s.story_id), s.sensitivity ->> 'family',
           (select g ->> 'domain' from jsonb_array_elements(s.graph -> 'nodes') g where (g ->> 'hop_id')::bigint = s.hero_stop limit 1), s.event_id
      from ripples.att_story_candidates s where s.featurable order by s.story_score desc, s.story_id limit 20
    on conflict do nothing;
    delete from ripples.att_story_featured where day < today - 60;
  end if;
  st := st || jsonb_build_object('cursor', cur, 'status', case when done then 'done' else 'running' end, 'rows', coalesce((st ->> 'rows')::int, 0) + n,
                                 'events', coalesce((st ->> 'events')::int, 0) + nev, 'finished', case when done then now() end, 'secs', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
  insert into ripples.att_state (k, v) values ('story.refresh', st) on conflict (k) do update set v = excluded.v, updated_at = now();
  return st;
end $fn$;
revoke all on function ripples.att_story_refresh(int) from anon, authenticated, public;
-- pg_cron: after finalize (08:20) and publish (08:25/08:40), before re-examination (08:55); a second pass finishes any remainder
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('att-story-refresh', 'att-story-refresh-2');
  perform cron.schedule('att-story-refresh',   '48 8 * * *', $c$select ripples.att_story_refresh(100)$c$);
  perform cron.schedule('att-story-refresh-2', '15,35 9 * * *', $c$select ripples.att_story_refresh(100)$c$);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Public read: rm_stories (ranked featured list for the home page). Only public lines (rm_is_public), only named nodes, quiet-mode flag,
--    the gated tier with the gate reason when demoted, no raw identifiers in text (rm_label_leaks asserted by the contract test).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.rm_story_item(s ripples.att_story_candidates) returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare ev ripples.att_events; lv jsonb; hero jsonb; hero_lbl text; nodes jsonb := '[]'::jsonb; g jsonb; lbl text; why jsonb := '[]'::jsonb; headline text; ver int;
        fe record; ex jsonb; wording text; days int; k int; rep jsonb; parent_lbl text; sentence text; rho numeric; unit text;
begin
  if s.story_kind = 'pattern' then
    select * into fe from ripples.att_family_effects v where v.grid_id = s.grid_id;
    if not found then return null; end if;
    ex := coalesce((select jsonb_agg(jsonb_build_object('event_id', e.event_id, 'label', coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), 'onset', e.onset,
                                                      'slug', case when ripples.rm_is_public(e.event_id) then ripples.rm_slug(e.event_id) end, 'quiet', ripples.rm_sensitive(e.event_id)) order by e.onset desc)
                      from jsonb_array_elements_text(s.replication -> 'example_event_ids') x join ripples.att_events e on e.event_id = x::bigint
                     where not ripples.att_story_off_limits(e.event_id) and not coalesce(ripples.rm_raw_id(coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), e.qid), false)   -- rm_raw_id is NULL when qid is null), '[]'::jsonb);
    headline := case when fe.sub = 'hurricane' then 'Hurricanes' else fe.family_label || 's' end || ' → ' || fe.outcome_label || ': ' || case when fe.pct >= 0 then '+' else '' end || fe.pct
                || case when (s.replication ->> 'unit') = 'raw' then ' (raw units)' else '%' end || ' over ' || fe.post_n || ' ' || case fe.grain when 'week' then 'weeks' else 'days' end
                || ', measured across ' || fe.n_events || ' past events';
    why := jsonb_build_array('affected vs unaffected regions, season-matched placebo events', 'strength: ' || fe.strength || case fe.strength when 'strong pattern' then ' (about 1 in 20 findings at this level could be a fluke)' when 'pattern' then ' (about 1 in 5 findings at this level could be a fluke)' else '' end)
           || case when (s.fields ->> 'domain_diversity')::int >= 2 then jsonb_build_array('crosses into a different domain (' || fe.domain_outcome || ')') else '[]'::jsonb end;
    return jsonb_build_object('story_id', s.story_id, 'kind', 'pattern', 'archetype', s.archetype, 'archetypes', to_jsonb(s.archetypes),
      'event', null, 'pattern', jsonb_build_object('id', fe.grid_id, 'family', fe.family, 'family_label', fe.family_label, 'sub', fe.sub, 'outcome_label', fe.outcome_label,
                                                   'n_events', fe.n_events, 'effect', fe.pct, 'ci', jsonb_build_array(fe.pct_lo, fe.pct_hi), 'unit', s.replication ->> 'unit', 'q', fe.q, 'p_placebo', fe.p_placebo,
                                                   'strength', fe.strength, 'window', jsonb_build_object('pre', fe.pre_n, 'post', fe.post_n, 'grain', fe.grain)),
      'tier', fe.strength, 'tier_wording', ripples.att_story_tier_wording(null, 'pattern'), 'engine_tier', fe.strength, 'demoted', false, 'gate_reason', null,
      'hero', null, 'spine', '[]'::jsonb, 'branches', '[]'::jsonb, 'graph', jsonb_build_object('nodes', '[]'::jsonb, 'edges', '[]'::jsonb), 'mediation_supported', true,
      'scores', ripples.rm_story_scores(s),
      'replication', jsonb_build_object('n_similar', fe.n_events, 'n_seen', (s.replication ->> 'n_seen')::int, 'n_strict', (s.replication ->> 'n_strict')::int, 'strength', fe.strength,
                                        'effect', fe.pct, 'wording', 'moved in the expected direction after ' || (s.replication ->> 'n_seen') || ' of ' || fe.n_events || ' past events', 'examples', ex,
                                        'this_event_regional', null),
      'watching', null, 'headline', headline, 'why', why, 'visual_density', jsonb_build_object('n', fe.n_events, 'bucket', case when fe.n_events <= 12 then 'sparse' when fe.n_events <= 40 then 'medium' else 'dense' end),
      'quiet', (s.sensitivity ->> 'quiet')::boolean, 'is_control', false, 'version', null, 'url', 'https://bensunter.com/ripples/patterns/#p' || fe.grid_id,
      'story_sentence', s.copy ->> 'story_sentence', 'short_title', s.copy ->> 'short_title', 'conversation_hook', s.copy ->> 'conversation_hook', 'share_line', s.copy ->> 'share_line',
      'travel', jsonb_build_object('domains_crossed', (s.travel ->> 'domains_crossed')::int, 'days', (s.travel ->> 'days')::int, 'depth', (s.travel ->> 'depth')::int),
      'share', ripples.rm_story_share(s, null), 'next', ripples.rm_story_next(s));
  end if;
  -- event-based stories: only public lines, only named nodes
  select * into ev from ripples.att_events where event_id = s.event_id;
  if not found or not ripples.rm_is_public(s.event_id) then return null; end if;
  select v.payload, v.version into lv, ver from ripples.rm_public_versions v where v.event_id = s.event_id order by v.version desc limit 1;
  for g in select x from jsonb_array_elements(s.graph -> 'nodes') x order by (x ->> 'depth')::int, (x ->> 'hop_id')::bigint loop
    continue when ripples.rm_node_hidden(g ->> 'node');
    lbl := ripples.rm_label_resolve(g ->> 'node', (select n2 ->> 'label' from jsonb_array_elements(coalesce(lv -> 'nodes', '[]'::jsonb) || coalesce(lv -> 'flat', '[]'::jsonb)) n2 where (n2 ->> 'hop_id')::bigint = (g ->> 'hop_id')::bigint limit 1));
    if lbl is null then lbl := ripples.rm_label_resolve(g ->> 'node', ripples.att_node_label(g ->> 'node')); end if;
    if lbl is null then return null; end if;
    nodes := nodes || (jsonb_build_object('kind', null, 'provisional', false, 'rho', null, 'unit', 'x', 'lag_days', null, 'onset', null, 'window_close', null,
                                          'p_1_in', null, 'f_1_in', null, 'channels', null, 'p_hat', null)   -- uniform node shape across kinds
                       || (g - 'node' - 'hidden') || jsonb_build_object('label', lbl));
  end loop;
  select x into hero from jsonb_array_elements(nodes) x where (x ->> 'hop_id')::bigint = s.hero_stop;
  if hero is null then return null; end if;
  hero_lbl := hero ->> 'label';
  rho := (hero ->> 'rho')::numeric; unit := coalesce(hero ->> 'unit', 'x');
  parent_lbl := ev.label;
  days := (hero ->> 'lag_days')::int;
  -- hero sentence: the ENGINE §8 template by public tier (never the Measured wording for anything else)
  sentence := case when s.tier = 'measured' and rho is not null then
                     format('%s ran %s for %s, starting %s %s. Measured movement, not proof of cause.', hero_lbl, ripples.rm_mult_phrase(rho, unit), ripples.rm_day_phrase((hero ->> 'onset')::date), ripples.rm_lag_phrase(days), parent_lbl)
                   when s.tier = 'likely' then format('%s: probably linked to %s; a fluke isn''t ruled out.%s', hero_lbl, parent_lbl,
                                                      case when rho is not null then ' Moved ' || ripples.rm_mult_phrase(rho, unit, true) || '.' else '' end)
                   when s.story_kind = 'watching' then format('%s: too early to tell. Window closes %s. Similar %s events: a move by then about 1 in %s times.', hero_lbl, s.watching ->> 'window_close',
                                                              lower(coalesce((select f.label from ripples.att_families f where f.family = ev.family), ev.family)), coalesce(s.watching ->> 'expected_1_in', '?'))
                   when s.story_kind = 'non_event' then format('%s: expected to move about 1 in %s times after %s; it stayed flat. The window closed %s without a detectable move.', hero_lbl,
                                                               coalesce(s.watching ->> 'expected_1_in', '?'), parent_lbl, coalesce(s.watching ->> 'window_close', ''))
                   else hero_lbl end;
  headline := case when s.story_kind = 'non_event' and s.archetype = 'Ghost' then format('%s: %s expected stops, none moved.', ev.label, s.fields ->> 'expected_stops')
                   when s.story_kind = 'non_event' then format('%s: the expected move in %s never came.', ev.label, hero_lbl)
                   when s.story_kind = 'watching' then format('%s: something is still being watched in %s.', ev.label, hero_lbl)
                   when s.tier = 'measured' then format('%s: %s later, something moved in %s.', ev.label, case when days = 0 then 'the same day' when days = 1 then '1 day' when days is null then 'soon' else days || ' days' end, hero_lbl)
                   else format('%s: %s may have moved.', ev.label, hero_lbl) end;
  rep := case when s.replication is not null then jsonb_build_object('n_similar', (s.replication ->> 'n_similar')::int, 'n_seen', (s.replication ->> 'n_seen')::int, 'n_strict', (s.replication ->> 'n_strict')::int,
             'strength', s.replication ->> 'strength', 'effect', (s.replication ->> 'effect_pct')::numeric,
             'wording', 'moved in the expected direction after ' || (s.replication ->> 'n_seen') || ' of ' || (s.replication ->> 'n_similar') || ' similar events',
             'examples', coalesce((select jsonb_agg(jsonb_build_object('event_id', e.event_id, 'label', coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), 'onset', e.onset,
                                                                   'slug', case when ripples.rm_is_public(e.event_id) then ripples.rm_slug(e.event_id) end, 'quiet', ripples.rm_sensitive(e.event_id)) order by e.onset desc)
                                    from jsonb_array_elements_text(s.replication -> 'example_event_ids') x join ripples.att_events e on e.event_id = x::bigint
                                   where not ripples.att_story_off_limits(e.event_id) and not coalesce(ripples.rm_raw_id(coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), e.qid), false)   -- rm_raw_id is NULL when qid is null), '[]'::jsonb),
             'this_event_regional', case when s.replication -> 'regional' is not null then jsonb_build_object('pass', (s.replication -> 'regional' ->> 'pass')::boolean, 'p_space', (s.replication -> 'regional' ->> 'p_space')::numeric) end) end;
  why := '[]'::jsonb;
  if (s.fields ->> 'mechanism_coherence')::float8 >= 0.9 then why := why || to_jsonb('a named mechanism at every step (mechanism library)'::text);
  elsif (s.fields ->> 'mechanism_coherence')::float8 >= 0.4 then why := why || to_jsonb('a mechanism at every step (Wikidata / reader-flow support)'::text); end if;
  if (s.fields ->> 'independent_confirmations')::int >= 2 then why := why || to_jsonb((s.fields ->> 'independent_confirmations') || ' independent confirmations'); end if;
  if rep is not null and (rep ->> 'n_seen')::int > 0 then why := why || to_jsonb(rep ->> 'wording'); end if;
  if (s.fields ->> 'surprise')::float8 >= 0.6 then why := why || to_jsonb('an unusual destination for this kind of event'::text); end if;
  if (s.fields ->> 'domain_diversity')::int >= 2 then why := why || to_jsonb('crosses ' || (s.fields ->> 'domain_diversity') || ' domains'); end if;
  if (s.fields ->> 'common_cause_risk')::float8 >= 0.5 then why := why || to_jsonb('drawn as a fork: the stops may share a cause rather than cause each other'::text); end if;
  if s.story_kind = 'watching' then why := why || to_jsonb(format('window closes in %s days; we expect a move about 1 in %s times', s.watching ->> 'days_to_resolve', coalesce(s.watching ->> 'expected_1_in', '?'))); end if;
  return jsonb_build_object('story_id', s.story_id, 'kind', s.story_kind, 'archetype', s.archetype, 'archetypes', to_jsonb(s.archetypes),
    'event', jsonb_build_object('event_id', ev.event_id, 'slug', ripples.rm_slug(ev.event_id), 'label', ev.label, 'emoji', coalesce(lv -> 'event' ->> 'emoji', ripples.rm_family_emoji(ev.family)),
                                'family', ev.family, 'onset', ev.onset, 'sensitive', ripples.rm_sensitive(ev.event_id), 'reconstructed', ev.reconstructed, 'is_control', ev.role = 'positive_control'),
    'pattern', null,
    'tier', s.tier, 'tier_wording', ripples.att_story_tier_wording(s.tier, s.story_kind), 'engine_tier', s.engine_tier, 'demoted', coalesce((s.gate ->> 'demoted')::boolean, false), 'gate_reason', s.gate ->> 'reason',
    'hero', jsonb_build_object('hop_id', s.hero_stop, 'label', hero_lbl, 'domain', hero ->> 'domain', 'tier', hero ->> 'tier', 'rho', hero -> 'rho', 'unit', unit, 'lag_days', hero -> 'lag_days',
                               'onset', hero -> 'onset', 'p_1_in', hero -> 'p_1_in', 'f_1_in', hero -> 'f_1_in', 'channels', coalesce(hero -> 'channels', jsonb_build_object('agree', 0, 'of', 0)), 'sentence', sentence),
    'spine', to_jsonb(s.spine), 'branches', to_jsonb(s.branches),
    'graph', jsonb_build_object('nodes', nodes, 'edges', s.graph -> 'edges'), 'mediation_supported', (s.fields ->> 'mediation_supported')::boolean,
    'scores', ripples.rm_story_scores(s), 'replication', rep,
    'watching', case when s.story_kind in ('watching','non_event') then s.watching - 'tier_reason' end,
    'headline', headline, 'why', why,
    'visual_density', jsonb_build_object('n', (s.fields ->> 'visual_density')::int, 'bucket', case when (s.fields ->> 'visual_density')::int <= 6 then 'sparse' when (s.fields ->> 'visual_density')::int <= 15 then 'medium' else 'dense' end),
    'quiet', (s.sensitivity ->> 'quiet')::boolean, 'is_control', (s.sensitivity ->> 'is_control')::boolean, 'version', ver,
    'url', 'https://bensunter.com/ripples/line/' || ripples.rm_slug(ev.event_id) || '/' || case when s.hero_stop is not null and s.story_kind <> 'non_event' then 'stop/' || s.hero_stop || '/' else '' end)
    -- D-16: first-class copy, travel, share identity and rabbit-hole pointers
    || jsonb_build_object('story_sentence', s.copy ->> 'story_sentence', 'short_title', s.copy ->> 'short_title', 'conversation_hook', s.copy ->> 'conversation_hook', 'share_line', s.copy ->> 'share_line',
                          'travel', jsonb_build_object('domains_crossed', (s.travel ->> 'domains_crossed')::int, 'days', (s.travel ->> 'days')::int, 'depth', (s.travel ->> 'depth')::int),
                          'share', ripples.rm_story_share(s, ver), 'next', ripples.rm_story_next(s));
end $fn$;
-- share identity (D-16 §1): canonical slug + frozen line version + first_seen + grown_since (compatible with rm_public_versions / grown_since)
create or replace function ripples.rm_story_share(s ripples.att_story_candidates, p_version int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'slug', case when s.story_kind = 'pattern' then 'pattern-' || s.grid_id else ripples.rm_slug(s.event_id) || case when s.story_kind = 'non_event' and s.archetype = 'Ghost' then '' else '-stop-' || s.hero_stop end end,
    'version', p_version, 'created_at', s.first_seen, 'refreshed_at', s.refreshed_at,
    'grown_since', case when s.event_id is null then null else
      (select case when prev.version is null then null else jsonb_build_object('version', prev.version, 'stops_added', ripples.rm_stops(cur.payload) - ripples.rm_stops(prev.payload)) end
         from (select v.version, v.payload from ripples.rm_public_versions v where v.event_id = s.event_id order by v.version desc limit 1) cur
         left join lateral (select v.version, v.payload from ripples.rm_public_versions v where v.event_id = s.event_id and v.version < cur.version order by v.version desc limit 1) prev on true) end,
    'og', case when s.story_kind = 'pattern' then null when s.story_kind = 'non_event' and s.archetype = 'Ghost' then 'v2/og/line-' || s.event_id || '-v' || p_version || '.png' else 'v2/og/stop-' || s.hero_stop || '.png' end,
    'reopen', jsonb_build_object('event_id', s.event_id, 'hop_id', s.hero_stop, 'version', p_version, 'grid_id', s.grid_id, 'kind', s.story_kind))
$$;
-- rabbit-hole pointers (D-16 §3): same event ("What else did X touch?"), same stop node elsewhere ("this stop connects to N other things"), same domain (lands), one more
create or replace function ripples.rm_story_next(s ripples.att_story_candidates) returns jsonb
language sql stable security definer set search_path = '' as $$
  with hero_node as (select g ->> 'node' node, g ->> 'domain' domain from jsonb_array_elements(s.graph -> 'nodes') g
                      where (s.hero_stop is not null and (g ->> 'hop_id')::bigint = s.hero_stop) or (s.story_kind = 'pattern') limit 1),
  pub as (select c.* from ripples.att_story_candidates c where c.featurable and c.copy is not null and c.story_id <> s.story_id
             and (c.event_id is null or ripples.rm_is_public(c.event_id)))
  select jsonb_build_object(
    'same_event', coalesce((select jsonb_agg(jsonb_build_object('story_id', p.story_id, 'short_title', p.copy ->> 'short_title', 'tier', p.tier, 'archetype', p.archetype) order by p.story_score desc)
                              from (select * from pub p0 where s.event_id is not null and p0.event_id = s.event_id order by p0.story_score desc limit 5) p), '[]'::jsonb),
    'same_stop', coalesce((select jsonb_agg(jsonb_build_object('story_id', p.story_id, 'short_title', p.copy ->> 'short_title', 'tier', p.tier, 'archetype', p.archetype) order by p.story_score desc)
                             from (select p0.* from pub p0, hero_node h where p0.event_id is distinct from s.event_id
                                     and exists (select 1 from jsonb_array_elements(p0.graph -> 'nodes') g where g ->> 'node' = h.node) order by p0.story_score desc limit 5) p), '[]'::jsonb),
    'stop_connections', (select count(distinct c.event_id) from ripples.att_hop_candidates c join ripples.att_events e on e.event_id = c.event_id, hero_node h
                          where c.node = h.node and c.frozen_hash is not null and e.role in ('real','library','positive_control') and c.event_id is distinct from s.event_id
                            and exists (select 1 from ripples.rm_public_versions v where v.event_id = c.event_id)),
    'same_domain', (select jsonb_build_object('domain', h.domain, 'url', 'https://bensunter.com/ripples/lands/' || h.domain || '/',
                                              'n_stories', (select count(*) from pub p0 where exists (select 1 from jsonb_array_elements(p0.graph -> 'nodes') g where (g ->> 'hop_id')::bigint = p0.hero_stop and g ->> 'domain' = h.domain)))
                      from hero_node h),
    'one_more', (select jsonb_build_object('story_id', p.story_id, 'short_title', p.copy ->> 'short_title', 'archetype', p.archetype)
                   from pub p where p.sensitivity ->> 'family' is distinct from s.sensitivity ->> 'family' order by p.story_score desc, p.story_id limit 1))
$$;
revoke all on function ripples.rm_story_share(ripples.att_story_candidates, int), ripples.rm_story_next(ripples.att_story_candidates) from anon, authenticated, public;
create or replace function ripples.rm_story_scores(s ripples.att_story_candidates) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('story', round(s.story_score::numeric, 3), 'coherence', round(s.coherence_score::numeric, 3),
    'temporal', (s.fields -> 'temporal_coherence'), 'mechanism', (s.fields -> 'mechanism_coherence'), 'evidence_at_transitions', (s.fields -> 'evidence_at_transitions'),
    'surprise', (s.fields -> 'surprise'), 'magnitude', (s.fields -> 'magnitude'), 'shock', (s.fields -> 'shock'), 'novelty', (s.fields -> 'novelty'),
    'shareability', (s.fields -> 'shareability'), 'visual_clarity', (s.fields -> 'visual_clarity'), 'common_cause_risk', (s.fields -> 'common_cause_risk'),
    'domain_diversity', (s.fields -> 'domain_diversity'), 'independent_confirmations', (s.fields -> 'independent_confirmations'),
    'branching_noise', (s.fields -> 'branching_noise'), 'length', (s.fields -> 'length'), 'replication', (s.fields -> 'replication'))
$$;
revoke all on function ripples.rm_story_item(ripples.att_story_candidates), ripples.rm_story_scores(ripples.att_story_candidates) from anon, authenticated, public;

create or replace function ripples.rm_stories_content(p_limit int default 12, p_days int default 90, p_kind text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  with cand as (
    select s.*, ripples.rm_story_item(s) item
      from ripples.att_story_candidates s
     where s.featurable and (p_kind is null or s.story_kind = p_kind)
       and coalesce((s.sensitivity ->> 'is_control')::boolean, false) = false        -- positive-control fixtures are never featured
       and (s.event_id is null or exists (select 1 from ripples.att_events e where e.event_id = s.event_id
                                              and e.onset >= (now() at time zone 'utc')::date - least(greatest(coalesce(p_days, 90), 1), 36500)))),
  ok as (select * from cand where item is not null),
  ranked as (select * from ok order by story_score desc, story_id limit least(greatest(coalesce(p_limit, 12), 1), 50))
  select jsonb_build_object('v', 2, 'as_of', (select max(refreshed_at) from ripples.att_story_candidates)::date,
    'rule', 'evidence tier decides what may be said (engine + forecast gate); story score decides what is shown first; a story can never upgrade a tier',
    'featured', coalesce((select jsonb_agg(item order by story_score desc, story_id) from ranked), '[]'::jsonb),
    'counts', coalesce((select jsonb_object_agg(a, n) from (select coalesce(archetype, 'Ripple') a, count(*) n from ok group by 1) x), '{}'::jsonb),
    'pool', jsonb_build_object('candidates', (select count(*) from ripples.att_story_candidates), 'featurable', (select count(*) from ripples.att_story_candidates where featurable),
                               'public', (select count(*) from ok), 'events_with_story', (select count(distinct event_id) from ok where event_id is not null)),
    'note', 'Consistent with, never proof of cause.')
$$;
revoke all on function ripples.rm_stories_content(int, int, text) from anon, authenticated, public;
create or replace function public.rm_stories(p_limit int default 12, p_days int default 90, p_kind text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select ripples.rm_stories_content(p_limit, p_days, case when p_kind in ('cascade','watching','non_event','pattern') then p_kind end)
$$;
revoke execute on function public.rm_stories(int, int, text) from public, anon, authenticated;
grant execute on function public.rm_stories(int, int, text) to anon, authenticated, service_role;
-- rm_grant_audit() (06_rm_public_rpcs.sql) is a hard-coded allowlist and rm_enforce_grants() revokes anything else at every publish:
-- 'rm_stories' (and 6.2's 'rm_patterns', 'rm_hop_fx62') were added to that allowlist (migration att_story_layer_p5_grant_allowlist).
grant execute on all functions in schema ripples to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Contract test for the separate RPC (fixture stories.json in rm_contract_fixtures) + leak guard
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.rm_story_contract_test() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare fx jsonb; act jsonb; diffs jsonb; leaks text[]; cov jsonb; kinds jsonb; bad_words int; demoted_bad int; wording_bad int;
begin
  select payload - '_comment' into fx from ripples.rm_contract_fixtures where name = 'stories.json';
  act := public.rm_stories(50, 36500, null);
  -- $.counts is a map keyed by archetype (rm_shape_diff map semantics); the kind-specific objects are null where a kind has none
  select coalesce(jsonb_agg(x), '[]'::jsonb) into diffs from ripples.rm_shape_diff(fx, act, '$', array['$.counts'], array['pattern','event','hero','watching','replication']) x;
  select jsonb_build_object('compared', count(*) filter (where c.state = 'compared'), 'vacuous', count(*) filter (where c.state = 'vacuous'),
                            'vacuous_paths', coalesce((select jsonb_agg(p) from (select c2.path p from ripples.rm_shape_cover(fx, act, '$', array['$.counts']) c2 where c2.state = 'vacuous' order by 1 limit 12) z), '[]'::jsonb))
    into cov from ripples.rm_shape_cover(fx, act, '$', array['$.counts']) c;
  leaks := ripples.rm_label_leaks(act, array['node','id','slug','url','story_id','payload_hash','ledger','template','spark','band','series','licences','sources','geo','code','family','sub','story','kind','archetype']);
  select count(*) into bad_words from jsonb_array_elements(act -> 'featured') f, jsonb_path_query(f, 'strict $.**') x
   where jsonb_typeof(x) = 'string' and (x #>> '{}') ~* '\m(caused|drove|because of|flooded into)\M';
  select count(*) into demoted_bad from jsonb_array_elements(act -> 'featured') f where (f ->> 'demoted')::boolean and (f ->> 'gate_reason') is null;
  select count(*) into wording_bad from jsonb_array_elements(act -> 'featured') f
   where coalesce(f ->> 'tier', '') <> 'measured' and ((f -> 'hero' ->> 'sentence') like '%Measured movement%' or (f ->> 'tier_wording') like '%Measured movement%');
  return jsonb_build_object('has_fixture', fx is not null, 'has_output', act is not null, 'diffs', diffs, 'coverage', cov, 'leaks', to_jsonb(leaks),
                            'causal_words', bad_words, 'demoted_without_reason', demoted_bad, 'measured_wording_on_lower_tier', wording_bad,
                            'ok', fx is not null and act is not null and jsonb_array_length(diffs) = 0 and cardinality(leaks) = 0 and bad_words = 0 and demoted_bad = 0 and wording_bad = 0);
end $$;
revoke all on function ripples.rm_story_contract_test() from anon, authenticated, public;
grant execute on function ripples.rm_story_contract_test() to service_role;

-- ---------------------------------------------------------------------------------------------
-- p7 (2026-09-26, orchestrator): per-event cap + fluke-sentence warming fix
-- 1. ripples.att_story_cap_per_event(p_dead_ends 2, p_watching 3): flips featurable -> false
--    (exclude_reason 'per_event_cap') for dead ends / Watching stops beyond the cap per event, so one
--    event (e.g. Milton's 12 dead ends) can't crowd stories.json. Never touches tiers/evidence.
--    pg_cron: att-story-cap-1 08:52, att-story-cap-2 09:19/09:39 (after each att-story-refresh run).
--    First run: 47 capped (non_event featurable 18 -> 4, watching 114 -> 81).
-- 2. ripples.rm_sentence (06): Measured sentence says "The fluke rate for links like this is still
--    being calibrated." when f1 is null OR f1 <= 1 OR node f_warming (was "flukes about 1 in 1 times").
--    rm_contract_test still ok. Applied as migrations att_story_per_event_cap, rm_sentence_fluke_warming.
create or replace function ripples.att_story_cap_per_event(p_dead_ends int default 2, p_watching int default 3)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare n_capped int;
begin
  with ranked as (
    select story_id, story_kind,
           row_number() over (partition by event_id, story_kind order by story_score desc nulls last, story_id) rk
    from ripples.att_story_candidates
    where featurable and story_kind in ('non_event','watching')
  ), cap as (
    update ripples.att_story_candidates c
       set featurable = false, exclude_reason = 'per_event_cap'
      from ranked r
     where c.story_id = r.story_id
       and ((r.story_kind = 'non_event' and r.rk > p_dead_ends) or (r.story_kind = 'watching' and r.rk > p_watching))
    returning 1)
  select count(*) into n_capped from cap;
  return jsonb_build_object('capped', n_capped);
end $f$;
revoke all on function ripples.att_story_cap_per_event(int,int) from public, anon, authenticated;
