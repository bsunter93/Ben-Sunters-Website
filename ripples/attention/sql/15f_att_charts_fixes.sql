-- 15f_att_charts_fixes (att-charts c8, 2026-09-25) — verifier follow-ups
-- 1) ripples.att_charts_prune(source, day, metric, geo, keep[]): a snapshot rank list holds exactly one list per
--    (metric, geo, as_of day). After a successful same-day re-run, rows written earlier that day for items that have
--    since dropped off the list are deleted (gh.search had 51 series for a top 50 on 2026-09-24). Restricted to the
--    snapshot-list sources; an empty keep list never deletes. Series rows are kept (other days may use them).
-- 2) att_state 'charts.tranco.top' no longer holds a readable top-1000 domain list: converted in place to one-way
--    12-hex SHA-256 digests in rank order ({day, h}), the format att-charts c8 reads and writes.
create or replace function ripples.att_charts_prune(p_source text, p_day date, p_metric text, p_geo text, p_keep text[])
returns int language plpgsql security definer set search_path = '' as $$
declare n int := 0;
begin
  if p_keep is null or cardinality(p_keep) = 0 or p_day is null then return 0; end if;
  if p_source not in ('apple.rss', 'steamspy', 'gh.search', 'hf.trending', 'anilist', 'ol.trending') then return 0; end if;
  -- anilist: only the trending list metrics are snapshots (metric 'n' is a per-media daily series)
  if p_source = 'anilist' and p_metric not in ('trending_anime', 'trending_manga') then return 0; end if;
  delete from ripples.attention_obs o
   using ripples.att_series s
   where o.series_id = s.series_id and o.day = p_day
     and s.source = p_source and s.metric = p_metric and s.geo = coalesce(p_geo, 'ALL')
     and not (s.key = any(p_keep));
  get diagnostics n = row_count;
  return n;
end $$;
create or replace function public.att_charts_prune(p_source text, p_day date, p_metric text, p_geo text, p_keep text[])
returns int language sql security definer set search_path = '' as $$
  select ripples.att_charts_prune(p_source, p_day, p_metric, p_geo, p_keep) $$;
do $$
declare f text;
begin
  foreach f in array array['ripples.att_charts_prune(text, date, text, text, text[])',
                           'public.att_charts_prune(text, date, text, text, text[])'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- 2) Tranco snapshot: readable list -> digests (idempotent: only rows that still carry 'list')
update ripples.att_state st
   set v = jsonb_build_object('day', st.v->>'day',
             'h', (select string_agg(substr(encode(sha256(convert_to(lower(d.x), 'UTF8')), 'hex'), 1, 12), '' order by d.i)
                     from jsonb_array_elements_text(st.v->'list') with ordinality d(x, i)))
       || case when st.v ? 'prev' and st.v->'prev' ? 'list' then jsonb_build_object('prev', jsonb_build_object(
             'day', st.v->'prev'->>'day',
             'h', (select string_agg(substr(encode(sha256(convert_to(lower(d.x), 'UTF8')), 'hex'), 1, 12), '' order by d.i)
                     from jsonb_array_elements_text(st.v->'prev'->'list') with ordinality d(x, i))))
               when st.v ? 'prev' then jsonb_build_object('prev', st.v->'prev') else '{}'::jsonb end,
       updated_at = now()
 where st.k = 'charts.tranco.top' and st.v ? 'list';
