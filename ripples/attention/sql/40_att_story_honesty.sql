-- 40: story layer v2.2 — honesty fixes from the 2026-09-27 vision sweep. Wording and tier mapping only; no test,
-- threshold or verdict of any batch changes.
--
-- 1. Outcome pages showed two engine-6.2 world rules ("strong pattern": pooled regional contrast, q ~ 0.04, never
--    re-tested on held-out events) as CONFIRMED, e.g. "Hurricanes (across 23 past events) - Confirmed" under new-business
--    applications, while the shock pages call the same rule "a lead, not a finding". A world rule is confirmed only when
--    it passed the held-out confirmation (strength 'confirmed pattern'); 'strong pattern' is shown as possible (a lead).
-- 2. "expected, not yet tested" on outcome pages meant "predicted", while "expected" everywhere else means "obvious".
--    Renamed to "predicted, not yet tested".
-- 3. A per-event impact tagged 'likely' whose own evidence says it is ordinary is no longer shown as a move: when more
--    than 1 in 10 ordinary days looked as strong (exceed_date / n_date > 0.10; e.g. inflation expectations after the
--    2026-09-11 CPI release: 10 of 36), it is listed with the things that didn't clearly move.
-- 4. An outcome group listed as "too early" AND "no sign" for the same shock (weather warnings for Milton and Helene,
--    both 2024: some tests flat, one never run) now shows once, as "no sign". "Too early" is kept for groups with no
--    flat test at all.
-- 5. "Absorbed" is scoped to what was measured: "Of the 8 things we measure, only the expected one moved: ...".
--    "Hurricane Helene was absorbed" on ~8 coarse state indicators overclaimed for a storm that killed 200+ people.

-- 1 + 2 ---------------------------------------------------------------------------------------------------------------
do $$ declare d text;
  a1 text := $a$'tier', case when pt ->> 'strength' in ('strong pattern', 'confirmed pattern') then 'confirmed' else 'possible' end,$a$;
  b1 text := $b$'tier', case when pt ->> 'strength' = 'confirmed pattern' then 'confirmed' else 'possible' end,$b$;
  a2 text := $a$when 'possible' then 'expected, not yet tested'$a$;
  b2 text := $b$when 'possible' then 'predicted, not yet tested'$b$;
begin
  d := pg_get_functiondef('ripples.att_explorer_build()'::regprocedure);
  if position(b2 in d) > 0 then return; end if;
  if position(a1 in d) = 0 or position(a2 in d) = 0 then raise exception 'explorer_build anchors'; end if;
  execute replace(replace(d, a1, b1), a2, b2);
end $$;

-- 3 + 4 + 5 -----------------------------------------------------------------------------------------------------------
do $$ declare d text;
  a0 text := $a$        none_names text[]; ctx jsonb := null;$a$;
  b0 text := $b$        none_names text[]; ctx jsonb := null; weak text[] := '{}'; n_meas int;$b$;
  a1 text := $a$    pl := case when coalesce(cardinality(r.places), 0) = 0 then null$a$;
  b1 text := $b$    -- 40/3: a 'likely' move that ordinary days match more than 1 time in 10 is not shown as a move
    if r.tier = 'likely' and coalesce(r.ex, '') ~ '^[0-9]+$' and coalesce(r.nd, '') ~ '^[0-9]+$' and r.nd::numeric > 0
       and r.ex::numeric / r.nd::numeric > 0.10 then
      weak := weak || r.gname::text;
      continue;
    end if;
    pl := case when coalesce(cardinality(r.places), 0) = 0 then null$b$;
  a2 text := $a$           where not exists (select 1 from jsonb_array_elements(imp) i where i ->> 'group' = gg.group_key)
           group by gg.group_key, gg.name, gg.short, gg.noun, gg.sort) q;$a$;
  b2 text := $b$           where not exists (select 1 from jsonb_array_elements(imp) i where i ->> 'group' = gg.group_key)
             and not exists (select 1 from jsonb_array_elements(coalesce(j -> 'flats', '[]')) f where (f ->> 'node') ~ gg.node_regex)   -- 40/4
           group by gg.group_key, gg.name, gg.short, gg.noun, gg.sort) q;$b$;
  a3 text := $a$  top := imp -> 0;$a$;
  b3 text := $b$  none_names := array(select x from unnest(none_names || weak) with ordinality u(x, o) group by x order by min(o));   -- 40/3
  n_meas := jsonb_array_length(imp) + coalesce(cardinality(none_names), 0);
  top := imp -> 0;$b$;
  a4 text := $a$    when 'absorbed' then 'Only the expected ripple: ' || lower(ripples.att_plain_list(exp_names)) || ' moved ' || ripples.att_plain_when(maxlag)
         || '. It died out there.'$a$;
  b4 text := $b$    when 'absorbed' then 'Of the ' || n_meas || ' things we measure, only the expected ' || case when cardinality(exp_names) > 1 then 'ones' else 'one' end
         || ' moved: ' || lower(ripples.att_plain_list(exp_names)) || ', ' || ripples.att_plain_when(maxlag) || '. It died out there.'$b$;
begin
  d := pg_get_functiondef('ripples.att_explorer_shock(text)'::regprocedure);
  if position('40/3' in d) > 0 then return; end if;
  if position(a0 in d) = 0 or position(a1 in d) = 0 or position(a2 in d) = 0 or position(a3 in d) = 0 or position(a4 in d) = 0 then
    raise exception 'explorer_shock anchors % % % % %', position(a0 in d), position(a1 in d), position(a2 in d), position(a3 in d), position(a4 in d);
  end if;
  execute replace(replace(replace(replace(replace(d, a0, b0), a1, b1), a2, b2), a3, b3), a4, b4);
end $$;

select ripples.att_explorer_build() is not null as rebuilt;
