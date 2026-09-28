-- 52: Q3 library lens export (ripples/lab/more_panels.py library; ripples/docs/q3_protocol_library.md). Read-only,
-- service_role only. Seattle Public Library monthly checkouts by subject, 2012-01..2026-08, in the same sparse format
-- as att_q3_export: {"sea|n|<subject>|US-WA-Seattle": {"d": day offsets from 2012-01-01, "v": counts}}.
create or replace function public.att_q3_sea_export() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(name, obj), '{}'::jsonb) from (
    select 'sea|n|' || term || '|US-WA-Seattle' as name,
           jsonb_build_object('d', jsonb_agg(ym - date '2012-01-01' order by ym), 'v', jsonb_agg(n order by ym)) as obj
      from ripples.att_sea where ym between date '2012-01-01' and date '2026-08-31' and n is not null
     group by term) t;
$$;
revoke all on function public.att_q3_sea_export() from anon, authenticated, public;
grant execute on function public.att_q3_sea_export() to service_role;
