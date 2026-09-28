-- 50: Q3 real-world lens export (ripples/lab/econ_panel.py, run on GitHub Actions; ripples/docs/q3_protocol_econ.md).
-- Read-only, service_role only. Daily behaviour-side series on the Wikipedia panel window 2015-07-01..2026-08-31:
-- EIA-930 electricity demand (balancing authorities and subregions), FRED daily markets and rates, TSA checkpoint
-- passengers. Each series is {"start": first day of the window, "v": one value per day, null where missing}.
create or replace function public.att_q3_econ_export() returns jsonb
language sql stable security definer set search_path = '' as $$
  with s as (
    select series_id, source || '|' || metric || '|' || key as name
      from ripples.att_series
     where (source = 'eia.930' and metric in ('demand', 'sub_demand'))
        or source = 'fred' or source = 'tsa.pax'),
  d as (select generate_series(date '2015-07-01', date '2026-08-31', interval '1 day')::date as day)
  select jsonb_build_object('start', '2015-07-01', 'series', jsonb_object_agg(s.name, v.vals))
    from s cross join lateral (
      select jsonb_agg(o.value order by d.day) as vals
        from d left join ripples.attention_obs o on o.series_id = s.series_id and o.day = d.day) v;
$$;
revoke all on function public.att_q3_econ_export() from anon, authenticated, public;
grant execute on function public.att_q3_econ_export() to service_role;
