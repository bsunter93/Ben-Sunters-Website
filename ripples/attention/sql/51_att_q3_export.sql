-- 51: generic Q3 export for further outcome lenses (ripples/lab/more_panels.py; ripples/docs/q3_protocol_more.md).
-- Read-only, service_role only. Returns every series of the named sources between 2012-01-01 and 2026-08-31, keyed
-- "source|metric|key|geo", as {"d": day offsets from 2012-01-01, "v": values} (sparse; weekly and monthly sources
-- need three prior years for seasonal adjustment). Called once per source to keep responses small.
create or replace function public.att_q3_export(p_source text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(name, obj), '{}'::jsonb) from (
    select s.source || '|' || s.metric || '|' || s.key || '|' || coalesce(s.geo, '') as name,
           jsonb_build_object('d', jsonb_agg(o.day - date '2012-01-01' order by o.day),
                              'v', jsonb_agg(o.value order by o.day)) as obj
      from ripples.att_series s join ripples.attention_obs o using (series_id)
     where s.source = p_source and o.day between date '2012-01-01' and date '2026-08-31' and o.value is not null
     group by 1) t;
$$;
revoke all on function public.att_q3_export(text) from anon, authenticated, public;
grant execute on function public.att_q3_export(text) to service_role;
