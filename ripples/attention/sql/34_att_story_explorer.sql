-- Story layer v2: the explorer (2026-09-27).
--
-- Owner direction: the interface exists to (1) guide people to a ripple and (2) let them explore a shock's downstream
-- impacts (one-to-many) and an outcome's upstream causes, in plain language suitable for a 12-year-old; statistics stay
-- under a deliberate "see the evidence" path. This layer SYNTHESISES; it never decides evidence:
--   * tiers come only from the engine's gated pond payloads (rm_pond: forecast gate applied) and the 6.2/6.3 pattern
--     tables of batches that are not withheld / not testable / superseded;
--   * Measured -> "Confirmed", Likely -> "Likely", a world-rule pattern that applies to this kind of shock but was not
--     tested on this event -> "Possible" (always worded as a lead, never a finding), pre-registered tests still waiting
--     for data -> "Too early", pre-registered tests that stayed flat -> "No sign";
--   * copy is template-built from engine facts (no free text, no generation at read time) and is sober for sensitive
--     events (no exclamation, no celebration words);
--   * several signals of the same kind for one shock (e.g. three power grids) are merged into one impact.
-- Output: ripples.att_explorer (one row), read by public.rm_explorer(); rebuilt by cron after the daily publish.

create table if not exists ripples.att_plain_groups (
  group_key text primary key,
  name text not null,              -- "Electricity demand"
  short text not null,             -- "Power use" (for tight labels)
  noun text not null,              -- "electricity use" (inside sentences)
  node_regex text not null,        -- matched against the engine node (source:key)
  place_regex text,                -- capture group 1 = place, applied to the engine title
  domain text not null,
  sort int not null default 100,
  place_one text,                  -- "on the % grid"
  place_many text                  -- "across % grids"
);
alter table ripples.att_plain_groups add column if not exists place_one text, add column if not exists place_many text;
create table if not exists ripples.att_plain_why (
  family_prefix text not null,     -- matched with like family_prefix || '%'
  group_key text not null,
  why text not null,
  primary key (family_prefix, group_key)
);
create table if not exists ripples.att_plain_family (
  family text primary key, kind text not null, plural text not null, sort int not null default 100
);
create table if not exists ripples.att_plain_next (      -- curated downstream LEADS (hypotheses, always "Possible")
  group_key text not null, next_key text not null, why text not null, primary key (group_key, next_key)
);
create table if not exists ripples.att_explorer (id int primary key default 1 check (id = 1), payload jsonb not null, built_at timestamptz not null default now());
alter table ripples.att_plain_groups enable row level security; alter table ripples.att_plain_why enable row level security;
alter table ripples.att_plain_family enable row level security; alter table ripples.att_plain_next enable row level security;
alter table ripples.att_explorer enable row level security;
revoke all on ripples.att_plain_groups, ripples.att_plain_why, ripples.att_plain_family, ripples.att_plain_next, ripples.att_explorer from anon, authenticated, public;

insert into ripples.att_plain_groups(group_key, name, short, noun, node_regex, place_regex, domain, sort) values
 ('power',     'Electricity demand',          'Power use',        'electricity use',             '^eia\.930:',                 '^(.*?) power grid$',                    'power', 10),
 ('bills',     'Electricity prices',          'Power prices',     'electricity prices',          '^bls\.cpi_items:.*(SEHF01|electric)', null,                             'prices', 20),
 ('newbiz',    'New-business applications',   'New businesses',   'applications to start a business', '^census\.bfs:',          null,                                    'business', 30),
 ('claims',    'Jobless claims',              'Jobless claims',   'jobless claims',              '^(fred\.claims|dol\.claims):', '^(.*?) initial jobless claims$',       'jobs', 40),
 ('gas',       'Gas prices',                  'Gas prices',       'gas prices',                  '^fred\.weekly:GAS',          null,                                    'prices', 50),
 ('jetfuel',   'Jet-fuel prices',             'Jet fuel',         'jet-fuel prices',             '^fred:DJFUEL',               null,                                    'prices', 55),
 ('natgas',    'Natural gas prices',          'Natural gas',      'natural gas prices',          '^fred:DHHNGSP',              null,                                    'prices', 56),
 ('rates2',    'Short-term interest rates',   '2-year yield',     'the 2-year Treasury yield',   '^fred:DGS2$',                null,                                    'markets', 60),
 ('rates10',   'Long-term interest rates',    '10-year yield',    'the 10-year Treasury yield',  '^fred:DGS10$',               null,                                    'markets', 61),
 ('inflexp',   'Inflation expectations',      'Inflation outlook','expected inflation',          '^fred:T(10|5)YIE',           null,                                    'markets', 62),
 ('dollar',    'The dollar',                  'Dollar',           'the dollar',                  '^fred:(DEX|DTWEX)',          null,                                    'markets', 63),
 ('devtools',  'AI developer tool downloads', 'Dev downloads',    'downloads of AI developer tools', '^(npm\.dl|pypi\.dl):',   '^(?:npm|PyPI) downloads of (.*)$',      'tech', 70),
 ('air',       'Air travel',                  'Air travel',       'air travel',                  '^tsa\.pax:',                 null,                                    'travel', 80),
 ('transit',   'Public transit',              'Transit',          'transit ridership',           '^mta\.ridership:',           '^(.*?) riders$',                        'travel', 81),
 ('fema',      'Disaster declarations',       'Declarations',     'federal disaster declarations', '^fema\.decl:',             '^FEMA declarations in (.*)$',           'government', 90),
 ('warnings',  'Weather warnings',            'Warnings',         'weather warnings',            '^iem\.warn:',                null,                                    'weather', 95),
 ('jobs',      'Jobs',                        'Jobs',             'jobs',                        '^fred\.state:.*NA$',         null,                                    'jobs', 42),
 ('localjobs', 'Local jobs',                  'Local jobs',       'local jobs',                  '^$',                         null,                                    'jobs', 43),
 ('gridalerts','Grid emergencies',            'Grid alerts',      'grid emergency alerts',       '^$',                         null,                                    'power', 12)
on conflict (group_key) do update set name = excluded.name, short = excluded.short, noun = excluded.noun, node_regex = excluded.node_regex,
  place_regex = excluded.place_regex, domain = excluded.domain, sort = excluded.sort;
update ripples.att_plain_groups set place_one = 'on the % grid', place_many = 'across % grids' where group_key = 'power';
update ripples.att_plain_groups set place_one = 'in %', place_many = 'in % states' where group_key in ('claims', 'fema');
update ripples.att_plain_groups set place_one = 'for %', place_many = 'for % packages' where group_key = 'devtools';
update ripples.att_plain_groups set place_one = 'on %', place_many = 'on % lines' where group_key = 'transit';

insert into ripples.att_plain_family(family, kind, plural, sort) values
 ('hazard.storm', 'Storm', 'storms', 10), ('hazard.heat', 'Heat', 'heat waves', 20), ('hazard.cold', 'Cold', 'cold snaps', 25),
 ('hazard.flood', 'Flood', 'floods', 30), ('hazard.wildfire', 'Wildfire', 'wildfires', 40), ('hazard.quake', 'Earthquake', 'earthquakes', 45),
 ('policy.macro_release', 'Economy', 'economic reports', 50), ('tech.model_release', 'Tech', 'AI model releases', 60)
on conflict (family) do update set kind = excluded.kind, plural = excluded.plural, sort = excluded.sort;

insert into ripples.att_plain_why(family_prefix, group_key, why) values
 ('hazard.storm', 'power',   'Wind and flooding cut power lines, and evacuated homes and closed shops use almost nothing.'),
 ('hazard.heat',  'power',   'Hot days mean air conditioners run harder, and they use a lot of electricity.'),
 ('hazard.cold',  'power',   'Heating runs harder on very cold days, and much of it is electric.'),
 ('hazard.storm', 'newbiz',  'After a hurricane, owners are rebuilding rather than launching, and banks and landlords pause.'),
 ('hazard.storm', 'gas',     'Gulf storms can shut refineries and ports that supply much of the country’s fuel.'),
 ('hazard.storm', 'fema',    'Big storms bring federal emergency help, which starts with a declaration.'),
 ('hazard.heat',  'bills',   'When demand spikes, utilities buy extra power at peak prices and pass some of it on.'),
 ('policy.macro_release', 'rates2',  'Short-term rates track what traders expect the central bank to do next, and an inflation surprise changes that.'),
 ('policy.macro_release', 'inflexp', 'A surprise inflation number changes what investors expect prices to do.'),
 ('tech.model_release', 'devtools', 'A surprise model release sends developers to try and compare alternatives.'),
 ('', 'power', 'Anything that changes how much people heat, cool or power their homes and workplaces shows up here.')
on conflict (family_prefix, group_key) do update set why = excluded.why;

insert into ripples.att_plain_next(group_key, next_key, why) values
 ('power',  'bills',      'Sustained high demand can push up the price utilities pay, and later bills.'),
 ('power',  'gridalerts', 'Very high demand days can trigger grid emergency alerts.'),
 ('newbiz', 'localjobs',  'Fewer new firms today can mean fewer new jobs later.'),
 ('devtools','devtools',  'A shift in one toolkit can spread to related packages.')
on conflict (group_key, next_key) do update set why = excluded.why;


create table if not exists ripples.att_plain_places (raw text primary key, plain text not null);
alter table ripples.att_plain_places enable row level security;
revoke all on ripples.att_plain_places from anon, authenticated, public;
insert into ripples.att_plain_places(raw, plain) values
 ('@anthropic-ai/sdk', 'Anthropic’s toolkit'), ('@modelcontextprotocol/sdk', 'the MCP toolkit'), ('openai', 'OpenAI’s toolkit'),
 ('langchain', 'LangChain'), ('ollama', 'Ollama'), ('anthropic', 'Anthropic’s Python toolkit'), ('transformers', 'Hugging Face Transformers'),
 ('torch', 'PyTorch'), ('Midcontinent ISO', 'the Midwest (MISO)'), ('LG&E and KU (Kentucky)', 'Kentucky (LG&E and KU)'),
 ('California ISO', 'California'), ('ERCOT (Texas)', 'Texas'), ('Northern California (BANC)', 'Northern California'),
 ('Duke Energy Carolinas', 'the Carolinas (Duke Energy)'), ('Duke Energy Progress East', 'eastern North Carolina')
on conflict (raw) do update set plain = excluded.plain;
alter table ripples.att_plain_groups add column if not exists obvious_for text;   -- family prefix for which this outcome is expected / definitional
update ripples.att_plain_groups set obvious_for = 'hazard.' where group_key in ('fema', 'warnings');

create or replace function ripples.att_plain_list(p text[], p_max int default 3) returns text
language sql immutable set search_path = '' as $$
  select case when p is null or cardinality(p) = 0 then ''
              when cardinality(p) = 1 then p[1]
              when cardinality(p) <= p_max then array_to_string(p[1:cardinality(p) - 1], ', ') || ' and ' || p[cardinality(p)]
              else array_to_string(p[1:p_max], ', ') || ' and ' || (cardinality(p) - p_max) || ' more' end
$$;
create or replace function ripples.att_plain_place(p text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select pl.plain from ripples.att_plain_places pl where pl.raw = p), p)
$$;

-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_plain_pct(p numeric) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null
              when abs(p) >= 95 then 'about ' || case when p > 0 then 'double' else 'half' end
              when abs(p) >= 45 then 'about half ' || case when p > 0 then 'more' else 'less' end
              when abs(p) between 8 and 13 then 'about a tenth ' || case when p > 0 then 'more' else 'less' end
              when abs(p) between 18 and 23 then 'about a fifth ' || case when p > 0 then 'more' else 'less' end
              else 'about ' || round(abs(p))::int || '% ' || case when p > 0 then 'more' else 'less' end end
$$;
create or replace function ripples.att_plain_when(d numeric) returns text
language sql immutable set search_path = '' as $$
  select case when d is null then 'in the days after' when d <= 1 then 'the next day' when d <= 8 then 'within a week'
              when d <= 35 then 'within a month' else 'within a few months' end
$$;
create or replace function ripples.att_plain_shock_name(p_name text, p_family text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_name ~* '^CPI release' then 'Inflation report'
    when p_name ~* '^Heat wave' then 'Heat wave' || coalesce(' across ' || substring(p_name from '\((\d+ states)\)'), '')
    when p_name ~* '^Cold' then 'Cold snap'
    else trim(regexp_replace(regexp_replace(regexp_replace(p_name, '\s*\((positive control|\d{4})\)', '', 'gi'),
                                            '\s*\((Fire|Flood|Hurricane|Severe Storm)[^)]*\)', '', 'gi'), '\s+', ' ', 'g')) end
$$;

-- one shock: pond payload -> explorer shock object
create or replace function ripples.att_explorer_shock(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare j jsonb; ev jsonb; fam text; fk record; name text; kind text; plural text; lplural text; sensitive boolean;
        imp jsonb := '[]'::jsonb; waits jsonb := '[]'::jsonb; leads jsonb := '[]'::jsonb;
        r record; top jsonb; reach numeric := 1; n_conf int := 0; n_like int := 0; synth text; title text; verdict text; conf text;
        none_names text[]; ctx jsonb := null;
        pl text; dir text; amt text; say text; sure text; why text; ev_rows jsonb; p jsonb; g record;
begin
  j := public.rm_pond(p_slug);
  if j is null then return null; end if;
  ev := j -> 'event';
  fam := coalesce(ev ->> 'family', (select x ->> 'family' from jsonb_array_elements(public.rm_pond() -> 'ponds') x where x ->> 'slug' = p_slug));
  select * into fk from ripples.att_plain_family f where f.family = fam;
  name := ripples.att_plain_shock_name(coalesce(ev ->> 'name', p_slug), fam);
  kind := coalesce(fk.kind, initcap(split_part(fam, '.', 2))); plural := coalesce(fk.plural, 'events like this');
  sensitive := coalesce((ev ->> 'sensitive')::boolean, false);

  -- confirmed / likely impacts, merged by plain group; own-normal change preferred, regional contrast otherwise
  for r in
    with e as (
      select gg.group_key, gg.name gname, gg.noun, gg.short, gg.place_one, gg.place_many,
             case when gg.place_regex is not null then ripples.att_plain_place(nullif(substring(coalesce(x ->> 'title', '') from gg.place_regex), '')) end place,
             (gg.obvious_for is not null and fam like gg.obvious_for || '%') obvious,
             case x ->> 'tier' when 'measured' then 'confirmed' else 'likely' end tier,
             coalesce(((x -> 'engine' -> 'rho' ->> 'shrunk')::numeric - 1) * 100,
                      (nullif(regexp_replace(coalesce(x ->> 'num', ''), '[^0-9.]', '', 'g'), '')::numeric - 1) * 100) pct_own,
             (x -> 'contrast' ->> 'effect_pct')::numeric pct_rel,
             coalesce((x ->> 'lag_from_event_days')::numeric, (x ->> 'lag_days')::numeric) lag,
             x -> 'engine' ->> 'exceed_date' ex, x -> 'engine' ->> 'n_date' nd, x -> 'contrast' ->> 'n_donors' donors,
             x -> 'published' -> 'ce' ->> 'state' ce
        from jsonb_array_elements(coalesce(j -> 'effects', '[]')) x
        join ripples.att_plain_groups gg on (x ->> 'node') ~ gg.node_regex
       where x ->> 'tier' in ('measured', 'likely'))
    select group_key, max(gname) gname, max(noun) noun, max(short) short, max(place_one) p_one, max(place_many) p_many,
           case when bool_or(tier = 'confirmed') then 'confirmed' else 'likely' end tier,
           array_agg(distinct place) filter (where place is not null) places,
           coalesce(avg(pct_own), avg(pct_rel)) pct, (avg(pct_own) is not null) own, avg(pct_rel) rel, min(lag) lag,
           max(ex) ex, max(nd) nd, max(donors) donors, bool_or(ce = 'agree') ce_agree, count(*) n, bool_or(obvious) obvious
      from e group by group_key
      order by bool_or(obvious), (case when bool_or(tier = 'confirmed') then 0 else 1 end), max(abs(coalesce(pct_own, pct_rel, 0))) desc
  loop
    pl := case when coalesce(cardinality(r.places), 0) = 0 then null
               when cardinality(r.places) = 1 then replace(coalesce(r.p_one, 'in %'), '%', r.places[1])
               else replace(coalesce(r.p_many, 'in % places'), '%', cardinality(r.places)::text) end;
    dir := case when r.pct is null then 'moved' when r.pct > 0 then 'up' else 'down' end;
    amt := ripples.att_plain_pct(round(r.pct::numeric, 1));
    say := upper(left(r.noun, 1)) || substring(r.noun from 2) || coalesce(' ' || pl, '')
           || case when amt is null then ' moved more than usual'
                   when r.own then ' ran ' || amt || ' than normal'
                   else ' ran ' || amt || ' than in places the shock missed' end
           || ' ' || ripples.att_plain_when(r.lag) || '.';
    sure := case r.tier
      when 'confirmed' then 'Very sure. ' || case when r.ce_agree and r.donors is not null then 'Three independent checks agree, and places the shock missed didn’t change.'
                                                   when r.donors is not null then 'Independent checks agree, and places the shock missed didn’t change.'
                                                   else 'It passed every check we run.' end
      else 'Fairly sure, but a fluke isn’t ruled out' || case when r.n > 1 then '. It showed up in ' || r.n || ' places at once.' else '.' end end;
    why := null;
    select w.why into why from ripples.att_plain_why w where fam like w.family_prefix || '%' and w.group_key = r.group_key order by length(w.family_prefix) desc limit 1;
    ev_rows := '[]'::jsonb;
    if r.ex is not null and r.nd is not null then ev_rows := ev_rows || jsonb_build_array(jsonb_build_array('Ordinary days that looked this strong', r.ex || ' of ' || to_char(r.nd::int, 'FM999,999'))); end if;
    if r.own and r.pct is not null then ev_rows := ev_rows || jsonb_build_array(jsonb_build_array('Change vs its own normal', (case when r.pct > 0 then '+' else '−' end) || abs(round(r.pct::numeric, 1)) || '%')); end if;
    if r.rel is not null then ev_rows := ev_rows || jsonb_build_array(jsonb_build_array('Change vs ' || coalesce(r.donors, 'other') || ' regions the shock missed', (case when r.rel > 0 then '+' else '−' end) || abs(round(r.rel::numeric, 1)) || '%')); end if;
    if r.ce_agree then ev_rows := ev_rows || jsonb_build_array(jsonb_build_array('Independent forecast model', 'agrees')); end if;
    ev_rows := ev_rows || jsonb_build_array(jsonb_build_array('Test registered before the result', 'yes'));
    imp := imp || jsonb_build_object('group', r.group_key, 'name', r.gname, 'short', r.short, 'tier', r.tier, 'dir', dir,
               'mag', case when r.pct is null then 'moved' else (case when r.pct > 0 then '+' else '−' end) || abs(round(r.pct))::int || '%' end,
               'at', greatest(coalesce(r.lag, 1), 1),
               'sub', coalesce(array_to_string(r.places[1:3], ', ') || case when cardinality(r.places) > 3 then ' +' || (cardinality(r.places) - 3) else '' end, r.gname)
                      || ' · ' || ripples.att_plain_when(r.lag),
               'say', say, 'why', coalesce(why, 'We don’t have a simple explanation yet.'), 'sure', sure, 'evidence', ev_rows);
    if r.tier = 'confirmed' then n_conf := n_conf + 1; else n_like := n_like + 1; end if;
    reach := greatest(reach, coalesce(r.lag, 1) + 6);
  end loop;

  -- possible: world rules for this kind of shock (never tested on this event; always worded as a lead)
  for r in select s from jsonb_array_elements(coalesce(j -> 'shore', '[]')) s loop
    p := r.s -> 'pattern';
    continue when p is null or coalesce(p ->> 'strength', '') not in ('strong pattern', 'confirmed pattern', 'confirmed pattern (weaker)');
    lplural := coalesce(lower(nullif(p ->> 'event_label', '')), plural);
    g := null;
    select * into g from ripples.att_plain_groups x where (p ->> 'outcome') ~ x.node_regex limit 1;
    continue when g.group_key is null or exists (select 1 from jsonb_array_elements(imp) i where i ->> 'group' = g.group_key)
                  or exists (select 1 from jsonb_array_elements(leads) i where i ->> 'group' = g.group_key);
    why := null;
    select w.why into why from ripples.att_plain_why w where fam like w.family_prefix || '%' and w.group_key = g.group_key order by length(w.family_prefix) desc limit 1;
    leads := leads || jsonb_build_object('group', g.group_key, 'name', g.name, 'short', g.short, 'tier', 'possible',
      'dir', case when (p ->> 'effect')::numeric > 0 then 'up' else 'down' end,
      'mag', '≈ ' || (case when (p ->> 'effect')::numeric > 0 then '+' else '−' end) || abs(round((p ->> 'effect')::numeric))::int || '%',
      'at', coalesce((r.s ->> 'lag_days')::numeric, 28), 'sub', 'seen after past ' || lplural,
      'say', 'After past ' || lplural || ', ' || g.noun || ' ran ' || ripples.att_plain_pct(round((p ->> 'effect')::numeric, 1)) || ' than in places they missed.',
      'why', coalesce(why, ''), 'sure', 'A lead, not a finding for this event. The pattern holds across ' || (p ->> 'n_events') || ' past ' || lplural || ', but we haven’t tested it here yet.',
      'evidence', jsonb_build_array(jsonb_build_array('Past events in the pattern', p ->> 'n_events'),
                                    jsonb_build_array('Average change', (case when (p ->> 'effect')::numeric > 0 then '+' else '−' end) || abs((p ->> 'effect')::numeric) || '%'),
                                    jsonb_build_array('Tested on this event', 'not yet')));
  end loop;

  -- too early: pre-registered tests waiting for data (merged by group)
  select coalesce(jsonb_agg(jsonb_build_object('group', q.group_key, 'name', q.name, 'short', q.short, 'tier', 'watch', 'dir', 'flat', 'mag', 'too early',
           'at', q.lag, 'sub', 'waiting for data', 'say', 'We’re checking whether ' || q.noun || ' moved.',
           'why', coalesce(q.why, ''), 'sure', 'Too early to tell. The test is registered; the data hasn’t arrived yet.',
           'evidence', jsonb_build_array(jsonb_build_array('Tests waiting', q.n::text), jsonb_build_array('Registered before the result', 'yes'))) order by q.sort), '[]'::jsonb)
    into waits
    from (select gg.group_key, gg.name, gg.short, gg.noun, gg.sort, count(*) n, max((u ->> 'lag_days')::numeric) lag,
                 (select w.why from ripples.att_plain_why w where fam like w.family_prefix || '%' and w.group_key = gg.group_key order by length(w.family_prefix) desc limit 1) why
            from jsonb_array_elements(coalesce(j -> 'untested', '[]')) u join ripples.att_plain_groups gg on (u ->> 'node') ~ gg.node_regex
           where not exists (select 1 from jsonb_array_elements(imp) i where i ->> 'group' = gg.group_key)
           group by gg.group_key, gg.name, gg.short, gg.noun, gg.sort) q;

  -- no sign: flat pre-registered tests (merged by group)
  select coalesce(array_agg(q.name order by q.sort), '{}') into none_names
    from (select distinct gg.name, gg.sort from jsonb_array_elements(coalesce(j -> 'flats', '[]')) f join ripples.att_plain_groups gg on (f ->> 'node') ~ gg.node_regex
           where not exists (select 1 from jsonb_array_elements(imp) i where i ->> 'group' = gg.group_key)) q;

  top := imp -> 0;
  conf := case when n_conf > 0 then 'confirmed' when n_like > 0 then 'likely' when jsonb_array_length(leads) > 0 then 'possible' else 'watch' end;
  title := case when top is not null then name || (case when conf = 'confirmed' then '’s clearest mark was on ' else ' probably moved ' end) || lower(top ->> 'name') || '.'
                when jsonb_array_length(waits) > 0 then name || ': still unfolding.'
                else name || ': no clear ripple.' end;
  synth := coalesce(top ->> 'say', '')
        || case when cardinality(none_names) > 0 then ' ' || case when top is null then 'So far, ' else 'Beyond that, ' end
                || lower(ripples.att_plain_list(none_names)) || ' didn’t move.' else '' end
        || case when jsonb_array_length(leads) > 0 then ' ' || upper(left(split_part(leads -> 0 ->> 'sub', 'seen after past ', 2), 1)) || substring(split_part(leads -> 0 ->> 'sub', 'seen after past ', 2) from 2)
                || ' like this have often moved ' || lower(leads -> 0 ->> 'name') || '; that’s the lead to follow.' else '' end
        || case when top is null and jsonb_array_length(waits) > 0 then ' We’re checking whether ' || lower(ripples.att_plain_list(array(select w ->> 'name' from jsonb_array_elements(waits) w))) || ' moved; results arrive as the data does.' else '' end;
  synth := trim(synth);
  verdict := concat_ws(' · ', nullif(n_conf || ' confirmed', '0 confirmed'), nullif(n_like || ' likely', '0 likely'),
                       nullif(jsonb_array_length(leads) || ' possible', '0 possible'), nullif(jsonb_array_length(waits) || ' too early', '0 too early'),
                       nullif(cardinality(none_names) || ' no sign', '0 no sign'));
  if jsonb_array_length(coalesce(j -> 'rivals', '[]')) > 0 then
    ctx := jsonb_build_object('title', 'Also in the water', 'text',
      (select string_agg(ripples.att_plain_shock_name(rv ->> 'name', fam) || ' came ' || (rv ->> 'days_before') || ' days earlier'
                         || case when (rv -> 'own_contrast' ->> 'pass')::boolean is false then '. We checked: its own ripple here was flat, so the change belongs to ' || name || '.' else '. Its ripple may overlap this one.' end, ' ')
         from jsonb_array_elements(j -> 'rivals') rv));
  end if;

  return jsonb_build_object('slug', p_slug, 'name', name, 'kind', kind, 'family', fam, 'plural', plural,
    'when', to_char((ev ->> 'onset')::date, 'Mon YYYY'), 'onset', ev ->> 'onset', 'where', coalesce(ev ->> 'place', ''), 'sensitive', sensitive,
    'is_control', coalesce((ev ->> 'is_control')::boolean, (ev ->> 'role') = 'positive_control', false),
    'confidence', conf, 'title', title, 'synth', synth, 'verdict', verdict,
    'reach', least(91, reach), 'impacts', imp || leads || waits, 'none', to_jsonb(none_names), 'context', ctx,
    'counts', jsonb_build_object('confirmed', n_conf, 'likely', n_like, 'possible', jsonb_array_length(leads), 'watch', jsonb_array_length(waits), 'none', cardinality(none_names)));
end $$;

create or replace function ripples.att_explorer_build() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare shocks jsonb := '[]'::jsonb; s jsonb; p jsonb; outcomes jsonb := '{}'::jsonb; g record; up jsonb; down jsonb; o jsonb;
begin
  for p in select x from jsonb_array_elements(public.rm_pond() -> 'ponds') x loop
    s := ripples.att_explorer_shock(p ->> 'slug');
    continue when s is null;
    shocks := shocks || s;
  end loop;
  -- order: confirmed first, then likely, possible, still unfolding; newest first inside each
  select coalesce(jsonb_agg(x order by case x ->> 'confidence' when 'confirmed' then 0 when 'likely' then 1 when 'possible' then 2 else 3 end, x ->> 'onset' desc), '[]') into shocks
    from jsonb_array_elements(shocks) x;

  -- outcomes (upstream view): every group that any shock or world rule touches
  for g in select * from ripples.att_plain_groups order by sort loop
    select coalesce(jsonb_agg(jsonb_build_object('shock', x ->> 'slug', 'name', x ->> 'name', 'tier', i ->> 'tier', 'dir', i ->> 'dir',
             'txt', case i ->> 'tier' when 'watch' then 'being checked' when 'possible' then 'expected, not yet tested'
                    else (case i ->> 'dir' when 'up' then 'up ' when 'down' then 'down ' else '' end) || coalesce(nullif(ltrim(i ->> 'mag', '+−-≈ '), 'moved'), 'moved') end)
             order by case i ->> 'tier' when 'confirmed' then 0 when 'likely' then 1 when 'possible' then 2 else 3 end), '[]'::jsonb) into up
      from jsonb_array_elements(shocks) x, jsonb_array_elements(x -> 'impacts') i where i ->> 'group' = g.group_key;
    -- world rules (patterns across many events) feeding this outcome
    select up || coalesce(jsonb_agg(jsonb_build_object('shock', null, 'name', upper(left(lower(coalesce(pt ->> 'event_label', f.plural)), 1)) || substring(lower(coalesce(pt ->> 'event_label', f.plural)) from 2) || ' (across ' || (pt ->> 'n_events') || ' past events)',
             'tier', case when pt ->> 'strength' like 'confirmed%' or pt ->> 'strength' = 'strong pattern' then 'confirmed' else 'possible' end,
             'dir', case when (pt ->> 'effect')::numeric > 0 then 'up' else 'down' end,
             'txt', (case when (pt ->> 'effect')::numeric > 0 then 'up about ' else 'down about ' end) || abs(round((pt ->> 'effect')::numeric))::int || '% on average')), '[]'::jsonb)
      into up
      from jsonb_array_elements(public.rm_patterns()) pt left join ripples.att_plain_family f on f.family = pt ->> 'family'
     where (pt ->> 'outcome') ~ g.node_regex and pt ->> 'strength' in ('strong pattern', 'confirmed pattern', 'hint');
    select coalesce(jsonb_agg(jsonb_build_object('group', n.next_key, 'name', gg.name, 'tier',
             coalesce((select 'watch' from jsonb_array_elements(shocks) x, jsonb_array_elements(x -> 'impacts') i where i ->> 'group' = n.next_key and i ->> 'tier' = 'watch' limit 1), 'possible'),
             'txt', n.why)), '[]'::jsonb) into down
      from ripples.att_plain_next n join ripples.att_plain_groups gg on gg.group_key = n.next_key where n.group_key = g.group_key and n.next_key <> g.group_key;
    continue when jsonb_array_length(up) = 0 and jsonb_array_length(down) = 0;
    continue when jsonb_array_length(up) = 0 and not exists (select 1 from ripples.att_plain_next n where n.next_key = g.group_key);
    outcomes := outcomes || jsonb_build_object(g.group_key, jsonb_build_object('key', g.group_key, 'name', g.name, 'short', g.short, 'domain', g.domain,
      'up', up, 'down', down,
      'synth', case when jsonb_array_length(up) = 0 then 'Nothing traced to ' || g.noun || ' yet. It’s on our list as a possible next step.'
               else (select string_agg(distinct x ->> 'name', ', ') from jsonb_array_elements(up) x where x ->> 'tier' in ('confirmed', 'likely')) end));
  end loop;
  o := jsonb_build_object('v', 1, 'built_at', now(), 'shocks', shocks, 'outcomes', outcomes,
    'tiers', jsonb_build_object(
      'confirmed', 'Passed every check we run.',
      'likely', 'Strong signal, but a fluke isn’t ruled out.',
      'possible', 'A lead worth following: seen after similar shocks, not tested on this one. Not a finding.',
      'watch', 'We’re waiting for the data.',
      'none', 'We looked, and nothing unusual happened.'),
    'note', 'Consistent with, never proof of cause.');
  insert into ripples.att_explorer(id, payload, built_at) values (1, o, now()) on conflict (id) do update set payload = excluded.payload, built_at = now();
  return jsonb_build_object('shocks', jsonb_array_length(shocks), 'outcomes', (select count(*) from jsonb_object_keys(outcomes)));
end $$;

create or replace function public.rm_explorer() returns jsonb
language sql stable security definer set search_path = '' as $$ select payload from ripples.att_explorer where id = 1 $$;
revoke all on function public.rm_explorer() from public;
grant execute on function public.rm_explorer() to anon, authenticated, service_role;
revoke all on function ripples.att_explorer_build(), ripples.att_explorer_shock(text) from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- Copy refinements applied live after review of the first build (anchor-checked; kept here so the file matches the DB):
alter table ripples.att_plain_family add column if not exists noun text;
update ripples.att_plain_family set noun = case family when 'hazard.storm' then 'the storm' when 'hazard.heat' then 'the heat wave' when 'hazard.cold' then 'the cold snap'
  when 'hazard.flood' then 'the flood' when 'hazard.wildfire' then 'the fire' when 'hazard.quake' then 'the quake' when 'policy.macro_release' then 'the report' when 'tech.model_release' then 'the release' end;
alter table ripples.att_plain_groups add column if not exists noun_place text;
update ripples.att_plain_groups set noun_place = 'downloads', place_one = 'of %', place_many = 'of % packages' where group_key = 'devtools';
create or replace function ripples.att_plain_lc1(p text) returns text language sql immutable set search_path = '' as $$
  select case when p is null then null when substring(p from 2 for 1) ~ '[A-Z]' then p else lower(left(p, 1)) || substring(p from 2) end $$;
do $$ declare def text; a text[]; b text[]; i int;
begin
  a := array[
   $x$select gg.group_key, gg.name gname, gg.noun, gg.short, gg.place_one, gg.place_many,$x$,
   $x$select group_key, max(gname) gname, max(noun) noun, max(short) short,$x$,
   $x$    say := upper(left(r.noun, 1)) || substring(r.noun from 2) || coalesce(' ' || pl, '')$x$,
   $x$else ' ran ' || amt || ' than in places the shock missed' end$x$,
   $x$then 'Three independent checks agree, and places the shock missed didn’t change.'$x$,
   $x$then 'Independent checks agree, and places the shock missed didn’t change.'$x$,
   $x$title := case when top is not null then name || (case when conf = 'confirmed' then '’s clearest mark was on ' else ' probably moved ' end) || lower(top ->> 'name') || '.'$x$,
   $x$|| ' like this have often moved ' || lower(leads -> 0 ->> 'name')$x$];
  b := array[
   $x$select gg.group_key, gg.name gname, gg.noun, gg.noun_place, gg.short, gg.place_one, gg.place_many,$x$,
   $x$select group_key, max(gname) gname, max(noun) noun, max(noun_place) noun_place, max(short) short,$x$,
   $x$    say := upper(left(case when pl is not null then coalesce(r.noun_place, r.noun) else r.noun end, 1)) || substring(case when pl is not null then coalesce(r.noun_place, r.noun) else r.noun end from 2) || coalesce(' ' || pl, '')$x$,
   $x$else ' ran ' || amt || ' than in places ' || coalesce(fk.noun, 'the shock') || ' missed' end$x$,
   $x$then 'Three independent checks agree, and places ' || coalesce(fk.noun, 'the shock') || ' missed didn’t change.'$x$,
   $x$then 'Independent checks agree, and places ' || coalesce(fk.noun, 'the shock') || ' missed didn’t change.'$x$,
   $x$title := case when top is not null then (case when name ~ '^(Heat wave|Inflation report|Cold snap)' then 'The ' || ripples.att_plain_lc1(name) else name end) || (case when conf = 'confirmed' then '’s clearest mark was on ' else ' probably moved ' end) || ripples.att_plain_lc1(top ->> 'name') || '.'$x$,
   $x$|| ' like this have often moved ' || ripples.att_plain_lc1(leads -> 0 ->> 'name')$x$];
  select pg_get_functiondef('ripples.att_explorer_shock(text)'::regprocedure) into def;
  if position('att_plain_lc1' in def) > 0 then return; end if;
  for i in 1..array_length(a,1) loop
    if position(a[i] in def) = 0 then raise exception 'anchor % missing', i; end if;
    def := replace(def, a[i], b[i]);
  end loop;
  execute def;
end $$;

select cron.schedule('att-explorer-build', '52 8 * * *', $c$set statement_timeout = '110s'; select ripples.att_explorer_build()$c$);

-- public.rm_explorer is an intended public read: add it to the grant-audit allowlist (anchor-checked).
do $$ declare def text; a text := $a$'rm_pond')$a$; b text := $b$'rm_pond', 'rm_explorer')$b$;
begin select pg_get_functiondef('ripples.rm_grant_audit()'::regprocedure) into def;
  if position('rm_explorer' in def) > 0 then return; end if;
  if (length(def) - length(replace(def, a, ''))) / length(a) <> 1 then raise exception 'rm_grant_audit anchor'; end if;
  execute replace(def, a, b); end $$;
