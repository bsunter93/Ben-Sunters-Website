-- 35: story layer v2.1 — surprise first (owner review 2026-09-27).
-- A link that anyone would predict (storm -> disaster declaration, inflation report -> inflation expectations) no longer
-- headlines a shock. Each impact carries expected = (family matches att_plain_groups.obvious_for, now a regex on family).
-- story: surprise (a non-obvious link moved) | absorbed (only expected links, all within ~a week, downstream flat)
--        | expected | unfolding | none.

update ripples.att_plain_groups g set obvious_for = v.re from (values
  ('power', '^hazard\.(heat|cold|storm)'), ('gridalerts', '^hazard\.(heat|cold|storm)'),
  ('gas', '^hazard\.storm'), ('natgas', '^hazard\.(cold|heat)'), ('air', '^hazard\.storm'),
  ('fema', '^hazard\.'), ('warnings', '^hazard\.'),
  ('inflexp', '^policy\.macro_release'), ('rates2', '^policy\.macro_release'), ('rates10', '^policy\.macro_release'), ('dollar', '^policy\.macro_release'),
  ('devtools', '^tech\.')) v(k, re) where g.group_key = v.k;

create or replace function ripples.att_explorer_shock(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare j jsonb; ev jsonb; fam text; fk record; name text; kind text; plural text; lplural text; sensitive boolean;
        imp jsonb := '[]'::jsonb; waits jsonb := '[]'::jsonb; leads jsonb := '[]'::jsonb;
        r record; top jsonb; sur jsonb; exp_names text[]; story text; maxlag numeric := 0; n_sur int := 0; reach numeric := 1; n_conf int := 0; n_like int := 0; synth text; title text; verdict text; conf text;
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
      select gg.group_key, gg.name gname, gg.noun, gg.noun_place, gg.short, gg.place_one, gg.place_many,
             case when gg.place_regex is not null then ripples.att_plain_place(nullif(substring(coalesce(x ->> 'title', '') from gg.place_regex), '')) end place,
             (gg.obvious_for is not null and fam ~ gg.obvious_for) obvious,
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
    select group_key, max(gname) gname, max(noun) noun, max(noun_place) noun_place, max(short) short, max(place_one) p_one, max(place_many) p_many,
           case when bool_or(tier = 'confirmed') then 'confirmed' else 'likely' end tier,
           array_agg(distinct place) filter (where place is not null) places,
           coalesce(avg(pct_own), avg(pct_rel)) pct, (avg(pct_own) is not null) own, avg(pct_rel) rel, min(lag) lag,
           max(ex) ex, max(nd) nd, max(donors) donors, bool_or(ce = 'agree') ce_agree, count(*) n, coalesce(bool_or(obvious), false) obvious
      from e group by group_key
      order by coalesce(bool_or(obvious), false), (case when bool_or(tier = 'confirmed') then 0 else 1 end), max(abs(coalesce(pct_own, pct_rel, 0))) desc
  loop
    pl := case when coalesce(cardinality(r.places), 0) = 0 then null
               when cardinality(r.places) = 1 then replace(coalesce(r.p_one, 'in %'), '%', r.places[1])
               else replace(coalesce(r.p_many, 'in % places'), '%', cardinality(r.places)::text) end;
    dir := case when r.pct is null then 'moved' when r.pct > 0 then 'up' else 'down' end;
    amt := ripples.att_plain_pct(round(r.pct::numeric, 1));
    say := (select upper(left(nn, 1)) || substring(nn from 2) from (select case when r.noun_place is not null and pl is not null then r.noun_place else r.noun end nn) z) || coalesce(' ' || pl, '')
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
               'say', say, 'why', coalesce(why, 'We don’t have a simple explanation yet.'), 'sure', sure, 'evidence', ev_rows,
               'expected', r.obvious);
    if not r.obvious then n_sur := n_sur + 1; end if;
    maxlag := greatest(maxlag, coalesce(r.lag, 1));
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
      'expected', coalesce(fam ~ g.obvious_for, false),
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
  select x into sur from jsonb_array_elements(imp) x where not coalesce((x ->> 'expected')::boolean, false) limit 1;
  select coalesce(array_agg(x ->> 'name'), '{}') into exp_names from jsonb_array_elements(imp) x where coalesce((x ->> 'expected')::boolean, false);
  conf := case when n_conf > 0 then 'confirmed' when n_like > 0 then 'likely' when jsonb_array_length(leads) > 0 then 'possible' else 'watch' end;
  -- story kind: lead with the link you would not have guessed; say plainly when a shock stopped at the obvious
  story := case when sur is not null then 'surprise'
                when top is not null and maxlag <= 8 and cardinality(none_names) > 0 then 'absorbed'
                when top is not null then 'expected'
                when jsonb_array_length(waits) > 0 or jsonb_array_length(leads) > 0 then 'unfolding'
                else 'none' end;
  title := case when name ~ '^(Heat wave|Inflation report|Cold snap)' then 'The ' || ripples.att_plain_lc1(name) else name end;   -- generic names read as 'The heat wave'
  title := case story
    when 'surprise' then title || ' reached ' || ripples.att_plain_lc1(sur ->> 'name') || '.'
    when 'absorbed' then title || case when fam like 'hazard.%' then ' was absorbed.' else ' stayed contained.' end
    when 'expected' then title || ': only the expected ripple so far.'
    when 'unfolding' then title || ': still unfolding.'
    else title || ': no clear ripple.' end;
  synth := case story
    when 'surprise' then (sur ->> 'say')
         || case when cardinality(exp_names) > 0 then ' That’s beyond the expected ripple in ' || lower(ripples.att_plain_list(exp_names)) || '.' else '' end
    when 'absorbed' then 'Only the expected ripple: ' || lower(ripples.att_plain_list(exp_names)) || ' moved ' || ripples.att_plain_when(maxlag)
         || '. It died out there.'
    when 'expected' then 'Only what you’d expect: ' || lower(left(top ->> 'say', 1)) || substring(top ->> 'say' from 2)
         || ' Nothing further downstream has shown up yet.'
    else '' end
        || case when cardinality(none_names) > 0 then ' ' || case when top is null then 'So far, ' when story = 'absorbed' then '' else 'Beyond that, ' end
                || case when story = 'absorbed' then upper(left(ripples.att_plain_list(none_names), 1)) || lower(substring(ripples.att_plain_list(none_names) from 2)) else lower(ripples.att_plain_list(none_names)) end
                || ' didn’t move.' else '' end
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
    'confidence', conf, 'story', story, 'title', title, 'synth', synth, 'verdict', verdict,
    'reach', least(91, reach), 'impacts', imp || leads || waits, 'none', to_jsonb(none_names), 'context', ctx,
    'counts', jsonb_build_object('surprise', n_sur, 'expected', cardinality(exp_names), 'confirmed', n_conf, 'likely', n_like, 'possible', jsonb_array_length(leads), 'watch', jsonb_array_length(waits), 'none', cardinality(none_names)));
end $$;

select ripples.att_explorer_build() is not null as rebuilt;
